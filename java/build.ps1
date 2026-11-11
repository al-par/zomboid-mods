# Builds 42\media\java\ReviveGil.jar. Needs a JDK 25+ (javac must read the game's
# Java 25 class files) and ZombieBuddy.jar in the game folder, which ZombieBuddy's install puts there.
param(
    [string]$GameDir = "C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid",
    [string]$JdkBin = ""
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$build = Join-Path $root "build"
$classes = Join-Path $build "classes"
$output = Join-Path $root "..\42\media\java\ReviveGil.jar"
$gameJar = Join-Path $GameDir "projectzomboid.jar"
$zbJar = Join-Path $GameDir "ZombieBuddy.jar"

function Find-Tool([string]$name) {
    if ($JdkBin) { return Join-Path $JdkBin "$name.exe" }
    if ($env:JAVA_HOME) {
        $candidate = Join-Path $env:JAVA_HOME "bin\$name.exe"
        if (Test-Path $candidate) { return $candidate }
    }
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw "$name not found. Install a JDK 25+ or pass -JdkBin <path to jdk\bin>."
}

$javac = Find-Tool "javac"
$jar = Find-Tool "jar"
foreach ($dep in @($gameJar, $zbJar)) {
    if (-not (Test-Path $dep)) { throw "$dep not found" }
}

if (Test-Path $build) { Remove-Item -Recurse -Force $build }
New-Item -ItemType Directory -Force $classes | Out-Null
New-Item -ItemType Directory -Force (Split-Path $output) | Out-Null

$sources = @(Get-ChildItem -Recurse (Join-Path $root "src") -Filter *.java | ForEach-Object { $_.FullName })
& $javac --release 17 -nowarn -Xlint:-classfile -cp "$gameJar;$zbJar" -d $classes @sources
if ($LASTEXITCODE -ne 0) { throw "javac failed" }

if (Test-Path $output) { Remove-Item -Force $output }
& $jar cf $output -C $classes .
if ($LASTEXITCODE -ne 0) { throw "jar failed" }
Remove-Item -Recurse -Force $build
Write-Host "Built $((Resolve-Path $output).Path)"
