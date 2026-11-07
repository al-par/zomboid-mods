# Builds ErrorMonitor-agent.jar next to this script. The agent never references game classes at compile
# time (hooks take Object parameters and are wired in by name), so any JDK 17+ works.
param(
    [string]$JdkBin = "",
    [string]$Output = "",
    [string]$Zig = ""
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$build = Join-Path $root "build"
$classes = Join-Path $build "classes"
$output = if ($Output) { $Output } else { Join-Path $root "ErrorMonitor-agent.jar" }
$libs = @(
    (Join-Path $root "lib\asm-9.9.jar"),
    (Join-Path $root "lib\asm-tree-9.9.jar")
)

function Find-Tool([string]$name) {
    if ($JdkBin) { return Join-Path $JdkBin "$name.exe" }
    if ($env:JAVA_HOME) {
        $candidate = Join-Path $env:JAVA_HOME "bin\$name.exe"
        if (Test-Path $candidate) { return $candidate }
    }
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw "$name not found. Install a JDK 17+ or pass -JdkBin <path to jdk\bin>."
}

$javac = Find-Tool "javac"
$jar = Find-Tool "jar"

if (Test-Path $build) { Remove-Item -Recurse -Force $build }
New-Item -ItemType Directory -Force $classes | Out-Null

$sources = Get-ChildItem -Recurse (Join-Path $root "src") -Filter *.java | ForEach-Object { $_.FullName }
& $javac --release 17 -nowarn -encoding UTF-8 -cp ($libs -join ";") -d $classes @sources
if ($LASTEXITCODE -ne 0) { throw "javac failed" }

# ASM is bundled inside the agent jar; the game does not ship it.
Push-Location $classes
try {
    foreach ($lib in $libs) {
        & $jar xf $lib
        if ($LASTEXITCODE -ne 0) { throw "could not unpack $lib" }
    }
    Remove-Item -Recurse -Force "META-INF" -ErrorAction SilentlyContinue
    Remove-Item -Force "module-info.class" -ErrorAction SilentlyContinue
} finally {
    Pop-Location
}

$manifest = Join-Path $build "MANIFEST.MF"
Set-Content -Path $manifest -Encoding ASCII -Value @(
    "Premain-Class: errormonitor.Agent",
    "Main-Class: errormonitor.Replay",
    "Can-Redefine-Classes: false",
    "Can-Retransform-Classes: false",
    ""
)

if (Test-Path $output) { Remove-Item -Force $output }
& $jar cfm $output $manifest -C $classes .
if ($LASTEXITCODE -ne 0) { throw "jar failed" }
Remove-Item -Recurse -Force $build
Write-Host "Built $output"

# The preload DLL rarely changes, so it is only rebuilt when a Zig compiler is given.
if ($Zig) {
    $dll = Join-Path $root "ErrorMonitor-preload.dll"
    & $Zig cc -shared -O2 -s -target x86_64-windows-gnu -o $dll (Join-Path $root "native\preload.c") -lkernel32
    if ($LASTEXITCODE -ne 0) { throw "zig cc failed" }
    Write-Host "Built $dll"
}
