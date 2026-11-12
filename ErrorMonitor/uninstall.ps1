# Removes the ErrorMonitor Java agent from the game's launch options. Other agents' entries are kept.
param(
    [string]$GameDir = "C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid"
)

$ErrorActionPreference = "Stop"

$json = Join-Path $GameDir "ProjectZomboid64.json"
if (Test-Path $json) {
    $text = [IO.File]::ReadAllText($json)
    $newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = $text -split "\r?\n"
    $kept = $lines | Where-Object { $_ -notmatch "ErrorMonitor-(agent\.jar|preload\.dll)" }
    if ($kept.Count -ne $lines.Count) {
        [IO.File]::WriteAllText($json, ($kept -join $newline), (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "Removed from $json"
    }
}

foreach ($name in "ProjectZomboid64.bat", "ProjectZomboid64ShowConsole.bat", "ProjectZomboidOpenGLDebug64.bat") {
    $bat = Join-Path $GameDir $name
    if (-not (Test-Path $bat)) { continue }
    $text = [IO.File]::ReadAllText($bat)
    $cleaned = [regex]::Replace($text, ' -javaagent:\S*ErrorMonitor-agent\.jar', '')
    if ($cleaned -ne $text) {
        [IO.File]::WriteAllText($bat, $cleaned)
        Write-Host "Removed from $bat"
    }
}

Write-Host "ErrorMonitor uninstalled. The recordings in Zomboid\ErrorMonitor are left in place."
