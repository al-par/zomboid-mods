-- Multiplayer only: the server breaks structures itself, so clients play the break sound here.

if not isClient() then return end

local MODULE = "SensibleLivestock"

local function onServerCommand(module, command, args)
    if module ~= MODULE or command ~= "breakSound" then return end
    local square = getCell():getGridSquare(args.x, args.y, args.z)
    if square and args.sound then square:playSound(args.sound) end
end

Events.OnServerCommand.Add(onServerCommand)
