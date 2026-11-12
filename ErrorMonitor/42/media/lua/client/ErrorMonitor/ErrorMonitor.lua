-- Build 42. In-game half of Error Monitor. The recording is done by the Java agent
-- (java/ErrorMonitor-agent.jar, added to the launch options by install.ps1). This file
-- 1. tells the agent the game state, save and active mods (ErrorMonitor_context.txt), and
-- 2. reads the agent's ErrorMonitor_status.txt and shows new errors in game.
-- Both files are in Zomboid\Lua. Text is English only, like the vanilla debug windows:
-- error messages are arbitrary text and must not go through getText's formatter.

require "ISUI/ISButton"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISRichTextPanel"

ErrorMonitor = {}

local CONTEXT_FILE = "ErrorMonitor_context.txt"
local STATUS_FILE = "ErrorMonitor_status.txt"
local SEEN_FILE = "ErrorMonitor_seen.txt"
local POLL_MS = 2000
-- The agent rewrites the status file every 2 seconds while the game runs.
local STALE_MS = 10000

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local PAD = 10

local WHITE = "1,1,1"
local GREY = "0.62,0.62,0.62"
local RED = "1,0.4,0.4"
local AMBER = "1,0.75,0.3"
local GREEN = "0.55,0.9,0.55"

local nextPoll = 0
local status = nil
local running = false
local seen = nil
local dismissedNotRunning = false

-- ---- context for the agent ----

local function writeContext(state)
	local writer = getFileWriter(CONTEXT_FILE, true, false)
	writer:write("state=" .. state .. "\n")
	writer:write("version=" .. tostring(getCore():getVersion()) .. "\n")
	writer:write("debug=" .. tostring(isDebugEnabled()) .. "\n")
	writer:write("mode=" .. (isClient() and "multiplayer" or "singleplayer") .. "\n")
	if state == "in game" then
		writer:write("gamemode=" .. tostring(getCore():getGameMode()) .. "\n")
		writer:write("save=" .. tostring(getWorld():getWorld()) .. "\n")
	end
	local mods = getActivatedMods()
	for i = 0, mods:size() - 1 do
		local id = mods:get(i)
		local info = getModInfoByID(id)
		writer:write("mod=" .. id .. "\t" .. (info and info:getName() or id) .. "\n")
	end
	-- The agent ignores the file until this line is there, so a half-written file is never read.
	writer:write("end\n")
	writer:close()
end

-- ---- status from the agent ----

local function readStatus()
	local reader = getFileReader(STATUS_FILE, false)
	if not reader then
		return nil
	end
	local result = { problems = {}, topMods = {} }
	local complete = false
	local line = reader:readLine()
	while line do
		if line == "end" then
			complete = true
		else
			local key, value = string.match(line, "^([^=]+)=(.*)$")
			if key == "problem" then
				local id, kind, count, mod, where, title = string.match(value, "^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
				if id then
					table.insert(result.problems, { id = id, error = kind == "error", count = tonumber(count) or 0, mod = mod, where = where, title = title })
				end
			elseif key == "topMod" then
				local name, amount = string.match(value, "^([^\t]*)\t(.*)$")
				if name then
					table.insert(result.topMods, { name = name, amount = amount })
				end
			elseif key then
				result[key] = value
			end
		end
		line = reader:readLine()
	end
	reader:close()
	if not complete then
		return nil
	end
	return result
end

local function number(value)
	return tonumber(value) or 0
end

-- ---- which problems the player has already looked at ----

local function loadSeen()
	seen = { session = "", crash = "", ids = {} }
	local reader = getFileReader(SEEN_FILE, false)
	if not reader then
		return
	end
	local line = reader:readLine()
	while line do
		local key, value = string.match(line, "^([^=]+)=(.*)$")
		if key == "session" then
			seen.session = value
		elseif key == "crash" then
			seen.crash = value
		elseif key == "seen" then
			seen.ids[value] = true
		end
		line = reader:readLine()
	end
	reader:close()
end

local function saveSeen()
	local writer = getFileWriter(SEEN_FILE, true, false)
	writer:write("session=" .. seen.session .. "\n")
	writer:write("crash=" .. seen.crash .. "\n")
	for id in pairs(seen.ids) do
		writer:write("seen=" .. id .. "\n")
	end
	writer:close()
end

local function syncSeenSession()
	if seen == nil then
		loadSeen()
	end
	-- Problem ids (E1, W1...) restart every session.
	if status and status.session and status.session ~= seen.session then
		seen.session = status.session
		seen.ids = {}
	end
end

local function markAllSeen()
	if not status then
		return
	end
	for _, p in ipairs(status.problems) do
		seen.ids[p.id] = true
	end
	seen.crash = status.previousCrash or ""
	saveSeen()
end

local function newErrorCount()
	local n = 0
	for _, p in ipairs(status.problems) do
		if p.error and not seen.ids[p.id] then
			n = n + 1
		end
	end
	return n
end

-- ---- report text, built once as rich text for the window and once as plain text for the clipboard ----

local Doc = {}
Doc.__index = Doc

local function newDoc()
	return setmetatable({ rich = {}, plain = {} }, Doc)
end

function Doc:add(color, text)
	-- The rich text panel treats any word containing < and > as a command.
	local safe = string.gsub(string.gsub(text, "<", "("), ">", ")")
	table.insert(self.rich, " <RGB:" .. color .. "> " .. safe)
	table.insert(self.plain, text)
end

function Doc:line()
	table.insert(self.rich, " <LINE> ")
	table.insert(self.plain, "\n")
end

function Doc:indent()
	table.insert(self.rich, " <SETX:28> ")
	table.insert(self.plain, "      ")
end

function Doc:heading(text)
	table.insert(self.rich, " <LINE> <H2> " .. text .. " <LINE> <TEXT> ")
	table.insert(self.plain, "\n" .. text .. "\n")
end

local function plural(n, one, many)
	return tostring(n) .. " " .. (n == 1 and one or many)
end

local function addPerformance(doc)
	doc:heading("PERFORMANCE")
	if (status.fps or "") == "" then
		doc:add(GREY, "No frames measured yet.")
		doc:line()
		return
	end
	local text = status.fps .. " fps on average, 99th percentile frame " .. status.frameP99 .. " ms"
	if (status.luaMsPerFrame or "") ~= "" then
		text = text .. ", Lua " .. status.luaMsPerFrame .. " ms per frame"
	end
	doc:add(WHITE, text .. ".")
	doc:line()
	local hitches, freezes = number(status.hitches), number(status.freezes)
	doc:add(hitches + freezes > 0 and AMBER or WHITE, plural(hitches, "hitch", "hitches") .. ", " .. plural(freezes, "freeze", "freezes") .. ". perf.txt says what caused each one.")
	doc:line()
	if #status.topMods > 0 then
		local parts = {}
		for _, m in ipairs(status.topMods) do
			local amount = m.amount
			if not string.find(amount, "%%$") then
				amount = amount .. " ms per frame"
			end
			table.insert(parts, m.name .. " " .. amount)
		end
		doc:add(GREY, "Most Lua time: " .. table.concat(parts, ", ") .. ".")
		doc:line()
	end
end

local function addProblems(doc, isError, highlight)
	local kinds, total
	if isError then
		kinds, total = number(status.errors), number(status.errorCount)
		doc:heading("ERRORS")
	else
		kinds, total = number(status.warnings), number(status.warningCount)
		doc:heading("WARNINGS")
	end
	if kinds == 0 then
		doc:add(isError and GREEN or GREY, isError and "No errors so far." or "No warnings so far.")
		doc:line()
		return
	end
	doc:add(GREY, plural(kinds, "different one", "different ones") .. ", " .. plural(total, "time", "times") .. " in total.")
	doc:line()
	local shown = 0
	for _, p in ipairs(status.problems) do
		if p.error == isError then
			shown = shown + 1
			local isNew = isError and (highlight[p.id] or not seen.ids[p.id])
			doc:add(isError and RED or AMBER, p.id .. "  " .. tostring(p.count) .. "x" .. (isNew and "  NEW" or ""))
			doc:add(WHITE, "  " .. (p.mod ~= "" and "[" .. p.mod .. "]  " or "") .. p.title)
			doc:line()
			if p.where ~= "" then
				doc:indent()
				doc:add(GREY, p.where)
				doc:line()
			end
		end
	end
	if shown < kinds then
		doc:add(GREY, "Only the first " .. tostring(shown) .. " are listed here. errors.txt has all of them.")
		doc:line()
	end
end

-- highlight: errors that were new when the window opened, so they stay marked after being seen.
local function buildReport(highlight)
	local doc = newDoc()
	if not running then
		doc:add(AMBER, "The Error Monitor recorder is not running, so this session is not being recorded.")
		doc:line()
		doc:add(GREY, "This mod only shows what the recorder (a Java agent) finds. Close the game, run install.ps1 in the mods\\ErrorMonitor folder, then start the game again.")
		doc:line()
		if status and status.session then
			doc:line()
			doc:add(GREY, "The last report came from session " .. status.session .. ".")
			doc:line()
		end
		return doc
	end
	doc:add(WHITE, "Session " .. (status.session or "?"))
	doc:add(GREY, "  errors.txt, session.log, perf.txt and performance.jfr are in its folder.")
	doc:line()
	if (status.previousCrash or "") ~= "" then
		doc:add(AMBER, "The previous session (" .. status.previousCrash .. ") did not end cleanly: the game crashed or was closed by force. Its folder has the log up to where it stopped.")
		doc:line()
	end
	addPerformance(doc)
	addProblems(doc, true, highlight)
	addProblems(doc, false, highlight)
	return doc
end

-- ---- window ----

ErrorMonitorWindow = ISCollapsableWindow:derive("ErrorMonitorWindow")

function ErrorMonitorWindow:createChildren()
	ISCollapsableWindow.createChildren(self)
	local th = self:titleBarHeight()
	local btnHgt = FONT_HGT_SMALL + 6

	self.richText = ISRichTextPanel:new(0, th, self.width, self.height - th - btnHgt - PAD * 2)
	self.richText:initialise()
	self.richText.background = false
	self.richText.autosetheight = false
	self.richText.clip = true
	self.richText.anchorRight = true
	self.richText.anchorBottom = true
	self:addChild(self.richText)
	self.richText:addScrollBars()

	local x = PAD
	local y = self.height - btnHgt - PAD
	local buttons = {
		{ "Open session folder", self.onOpenFolder },
		{ "Copy as text", self.onCopy },
		{ "Close", self.close },
	}
	for _, def in ipairs(buttons) do
		local width = getTextManager():MeasureStringX(UIFont.Small, def[1]) + 20
		local button = ISButton:new(x, y, width, btnHgt, def[1], self, def[2])
		button:initialise()
		button.anchorTop = false
		button.anchorBottom = true
		self:addChild(button)
		if def[2] == self.onOpenFolder then
			self.folderButton = button
		end
		x = button:getRight() + PAD
	end
end

function ErrorMonitorWindow:refresh()
	local doc = buildReport(self.highlight)
	local rich = table.concat(doc.rich)
	self.plainText = table.concat(doc.plain)
	self.folderButton:setEnable(running and status ~= nil and (status.folder or "") ~= "")
	if rich == self.richText.text then
		return
	end
	local scroll = self.richText:getYScroll()
	self.richText.text = rich
	self.richText:paginate()
	self.richText:setYScroll(scroll)
end

function ErrorMonitorWindow:onOpenFolder()
	showFolderInDesktop(status.folder)
end

function ErrorMonitorWindow:onCopy()
	Clipboard.setClipboard(self.plainText)
end

function ErrorMonitorWindow:close()
	self:setVisible(false)
	self:removeFromUIManager()
	ErrorMonitor.window = nil
end

function ErrorMonitorWindow:new(x, y, width, height)
	local o = ISCollapsableWindow.new(self, x, y, width, height)
	o.title = "Error Monitor"
	o.highlight = {}
	o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.9 }
	return o
end

-- ---- badge ----

local function openWindow()
	if ErrorMonitor.window then
		ErrorMonitor.window:bringToTop()
	else
		local width = math.min(900, getCore():getScreenWidth() - 40)
		local height = math.min(560, getCore():getScreenHeight() - 80)
		local window = ErrorMonitorWindow:new((getCore():getScreenWidth() - width) / 2, (getCore():getScreenHeight() - height) / 2, width, height)
		window:initialise()
		window:addToUIManager()
		ErrorMonitor.window = window
	end
	if status then
		for _, p in ipairs(status.problems) do
			if p.error and not seen.ids[p.id] then
				ErrorMonitor.window.highlight[p.id] = true
			end
		end
	end
	ErrorMonitor.window:refresh()
	if running then
		markAllSeen()
	else
		dismissedNotRunning = true
	end
	ErrorMonitor.updateBadge()
end

local function badgeContent()
	if not running then
		if dismissedNotRunning then
			return nil
		end
		return "Error Monitor is not recording", AMBER, 1
	end
	local fresh = newErrorCount()
	if fresh > 0 then
		return "Error Monitor: " .. plural(fresh, "new error", "new errors"), RED, 1
	end
	if (status.previousCrash or "") ~= "" and status.previousCrash ~= seen.crash then
		return "Error Monitor: the last session did not end cleanly", AMBER, 1
	end
	local errors = number(status.errors)
	if errors > 0 then
		return "Error Monitor: " .. plural(errors, "error", "errors"), GREY, 0.6
	end
	return nil
end

function ErrorMonitor.updateBadge()
	local text, color, alpha = badgeContent()
	local badge = ErrorMonitor.badge
	if not text then
		if badge then
			badge:setVisible(false)
		end
		return
	end
	if not badge then
		badge = ISButton:new(0, 2, 10, FONT_HGT_SMALL + 6, "", nil, openWindow)
		badge:initialise()
		badge:setAlwaysOnTop(true)
		badge:addToUIManager()
		ErrorMonitor.badge = badge
	end
	local r, g, b = string.match(color, "^([^,]+),([^,]+),([^,]+)$")
	badge.textColor = { r = tonumber(r), g = tonumber(g), b = tonumber(b), a = alpha }
	badge.borderColor = { r = tonumber(r), g = tonumber(g), b = tonumber(b), a = 0.5 * alpha }
	badge.backgroundColor = { r = 0, g = 0, b = 0, a = 0.6 * alpha }
	badge:setTitle(text)
	local width = getTextManager():MeasureStringX(UIFont.Small, text) + 20
	badge:setWidth(width)
	badge:setX((getCore():getScreenWidth() - width) / 2)
	badge:setVisible(true)
end

-- ---- polling ----

local function poll()
	local now = getTimestampMs()
	if now < nextPoll then
		return
	end
	nextPoll = now + POLL_MS
	local latest = readStatus()
	if latest then
		status = latest
	end
	running = status ~= nil and now - number(status.heartbeat) < STALE_MS
	syncSeenSession()
	ErrorMonitor.updateBadge()
	if ErrorMonitor.window then
		ErrorMonitor.window:refresh()
	end
end

-- OnGameBoot also fires while a save loads, which the agent reports as "at the main menu or loading a save".
Events.OnGameBoot.Add(function() writeContext("main menu") end)
Events.OnMainMenuEnter.Add(function() writeContext("main menu") end)
Events.OnGameStart.Add(function() writeContext("in game") end)
Events.OnPreUIDraw.Add(poll)
