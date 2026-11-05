# Adds the CutawayFix Java agent to the game's launch options: ProjectZomboid64.json (normal Steam launch)
# and the .bat files used by Steam's alternate launch options.
# Re-run after a game update or a Steam "verify files", which restore the original files.
param(
    [string]$GameDir = "C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid"
)

$ErrorActionPreference = "Stop"
$agent = Join-Path $PSScriptRoot "java\CutawayFix-agent.jar"
if (-not (Test-Path $agent)) { throw "Agent jar missing: $agent (run java\build.ps1)" }
$agentPath = (Resolve-Path $agent).Path.Replace("\", "/")
# ProjectZomboid64.exe needs this native agent listed first so instrument.dll can find the game JRE's DLLs.
$preload = Join-Path $PSScriptRoot "java\CutawayFix-preload.dll"
if (-not (Test-Path $preload)) { throw "Preload DLL missing: $preload (run java\build.ps1)" }
$preloadPath = (Resolve-Path $preload).Path.Replace("\", "/")
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Save-Backup([string]$path, [string]$text) {
    $backup = "$path.cutawayfix-backup"
    if (-not (Test-Path $backup)) {
        [IO.File]::WriteAllText($backup, $text)
    }
}

$json = Join-Path $GameDir "ProjectZomboid64.json"
if (-not (Test-Path $json)) { throw "ProjectZomboid64.json not found in $GameDir" }
$text = [IO.File]::ReadAllText($json)
Save-Backup $json $text
$newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
# Drop any earlier CutawayFix entry so re-running after moving the mod folder updates the path.
$text = ($text -split "\r?\n" | Where-Object { $_ -notmatch "CutawayFix-(agent\.jar|preload\.dll)" }) -join $newline
$anchor = [regex]::Match($text, '"vmArgs"\s*:\s*\[')
if (-not $anchor.Success) { throw "Could not find vmArgs in $json" }
$text = $text.Insert($anchor.Index + $anchor.Length, "$newline`t`t`"-agentpath:$preloadPath`",$newline`t`t`"-javaagent:$agentPath`",")
[IO.File]::WriteAllText($json, $text, $utf8)
Write-Host "Patched $json"

foreach ($name in "ProjectZomboid64.bat", "ProjectZomboid64ShowConsole.bat", "ProjectZomboidOpenGLDebug64.bat") {
    $bat = Join-Path $GameDir $name
    if (-not (Test-Path $bat)) { continue }
    $text = [IO.File]::ReadAllText($bat)
    Save-Backup $bat $text
    $text = [regex]::Replace($text, ' -javaagent:\S*CutawayFix-agent\.jar', '')
    $text = $text.Replace('".\jre64\bin\java.exe"', "`".\jre64\bin\java.exe`" -javaagent:$agentPath")
    [IO.File]::WriteAllText($bat, $text)
    Write-Host "Patched $bat"
}

Write-Host "CutawayFix installed. Originals saved as *.cutawayfix-backup"
