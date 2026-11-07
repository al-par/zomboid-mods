# Adds the ErrorMonitor Java agent to the game's launch options: ProjectZomboid64.json (normal Steam launch)
# and the .bat files used by Steam's alternate launch options. Other agents' entries (CutawayFix) are kept.
# Re-run after a game update or a Steam "verify files", which restore the original files.
param(
    [string]$GameDir = "C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid"
)

$ErrorActionPreference = "Stop"
$agent = Join-Path $PSScriptRoot "java\ErrorMonitor-agent.jar"
if (-not (Test-Path $agent)) { throw "Agent jar missing: $agent (run java\build.ps1)" }
$agentPath = (Resolve-Path $agent).Path.Replace("\", "/")
# ProjectZomboid64.exe needs this native agent listed first so instrument.dll can find the game JRE's DLLs.
$preload = Join-Path $PSScriptRoot "java\ErrorMonitor-preload.dll"
if (-not (Test-Path $preload)) { throw "Preload DLL missing: $preload (run java\build.ps1)" }
$preloadPath = (Resolve-Path $preload).Path.Replace("\", "/")
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Save-Backup([string]$path, [string]$text) {
    $backup = "$path.errormonitor-backup"
    if (-not (Test-Path $backup)) {
        [IO.File]::WriteAllText($backup, $text)
    }
}

$json = Join-Path $GameDir "ProjectZomboid64.json"
if (-not (Test-Path $json)) { throw "ProjectZomboid64.json not found in $GameDir" }
$text = [IO.File]::ReadAllText($json)
Save-Backup $json $text
$newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
# Drop any earlier ErrorMonitor entry so re-running after moving the mod folder updates the path.
$text = ($text -split "\r?\n" | Where-Object { $_ -notmatch "ErrorMonitor-(agent\.jar|preload\.dll)" }) -join $newline
$anchor = [regex]::Match($text, '"vmArgs"\s*:\s*\[')
if (-not $anchor.Success) { throw "Could not find vmArgs in $json" }
# First in the list, so it is recording before other agents start.
$text = $text.Insert($anchor.Index + $anchor.Length, "$newline`t`t`"-agentpath:$preloadPath`",$newline`t`t`"-javaagent:$agentPath`",")
[IO.File]::WriteAllText($json, $text, $utf8)
Write-Host "Patched $json"

foreach ($name in "ProjectZomboid64.bat", "ProjectZomboid64ShowConsole.bat", "ProjectZomboidOpenGLDebug64.bat") {
    $bat = Join-Path $GameDir $name
    if (-not (Test-Path $bat)) { continue }
    $text = [IO.File]::ReadAllText($bat)
    Save-Backup $bat $text
    $text = [regex]::Replace($text, ' -javaagent:\S*ErrorMonitor-agent\.jar', '')
    $text = $text.Replace('".\jre64\bin\java.exe"', "`".\jre64\bin\java.exe`" -javaagent:$agentPath")
    [IO.File]::WriteAllText($bat, $text)
    Write-Host "Patched $bat"
}

Write-Host "ErrorMonitor installed. Originals saved as *.errormonitor-backup. Restart the game for it to take effect."
