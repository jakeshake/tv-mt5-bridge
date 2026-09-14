# Provisions MT5 + the ZeroMQ EA inside the dockur/windows VM.
#
# NOTE ON CONFIDENCE: steps 1-4 below were run live against a real
# dockur/windows instance (Jake's Unraid box) on 2026-09-13 and fixed up
# based on what actually happened, notably:
#   - mt5setup.exe's /auto flag does NOT make it fully silent -- it still
#     shows a license-agreement screen and a finish screen that each need
#     a click. Automated below via SendKeys since MetaQuotes doesn't
#     document a fully-silent flag. This SendKeys loop has not itself been
#     re-verified after being added -- watch provision.log / the noVNC
#     console on first boot.
#   - The ding9736/MQL5-ZeroMQ repo's actual layout is Core/*.mqh +
#     ZeroMQ.mqh at the repo root (the library's own README describes an
#     older "ZeroMQ folder" layout that no longer matches) -- fixed below.
# Steps 5-6 (startup ini + auto-launch) are still unverified -- watch
# provision.log on first boot and confirm Algo Trading / DLL imports end
# up enabled (Tools > Options > Expert Advisors inside the terminal)
# before trusting this unattended. See docs/mt5-ea-setup.md for the
# manual fallback steps.

$ErrorActionPreference = "Stop"

$InstallDir   = "C:\MT5"
$MqlDir       = Join-Path $InstallDir "MQL5"
$ExpertsDir   = Join-Path $MqlDir "Experts"
$IncludeDir   = Join-Path $MqlDir "Include"
$LibrariesDir = Join-Path $MqlDir "Libraries"
$ConfigDir    = Join-Path $InstallDir "config"

New-Item -ItemType Directory -Force -Path $InstallDir, $ExpertsDir, $IncludeDir, $LibrariesDir, $ConfigDir | Out-Null

# ---------------------------------------------------------------------------
# 1. Install the MT5 terminal (generic MetaQuotes build; you log into your
#    own broker account inside it afterwards -- no broker-specific installer
#    is assumed here).
# ---------------------------------------------------------------------------
Write-Host "Downloading MT5 installer..."
$mt5Setup = "C:\OEM\mt5setup.exe"
Invoke-WebRequest -Uri "https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe" -OutFile $mt5Setup

Write-Host "Installing MT5 to $InstallDir ..."
$installProc = Start-Process -FilePath $mt5Setup -ArgumentList "/auto", "/dir=`"$InstallDir`"" -PassThru

# /auto still shows a license-agreement screen and a finish screen that
# each need a click (confirmed live) -- send Enter to whichever setup
# window has focus every couple seconds until the process exits.
$wshell = New-Object -ComObject WScript.Shell
$deadline = (Get-Date).AddMinutes(5)
while (-not $installProc.HasExited -and (Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 2
    if ($wshell.AppActivate($installProc.Id)) {
        Start-Sleep -Milliseconds 500
        $wshell.SendKeys("{ENTER}")
    }
}
if (-not $installProc.HasExited) {
    Write-Host "WARNING: MT5 installer still running after 5 minutes -- check the desktop."
    $installProc.WaitForExit()
}

# The installer's "Finish" screen auto-launches a non-portable terminal64
# and opens a browser registration page (confirmed live) -- neither is
# wanted here since step 6 launches our own portable-mode instance.
Get-Process terminal64 -ErrorAction SilentlyContinue | Stop-Process -Force

# ---------------------------------------------------------------------------
# 2. Fetch the ding9736/MQL5-ZeroMQ library (headers + libzmq/libsodium DLLs)
#    at provision time rather than vendoring a third-party binary in this
#    repo. Pin to a commit/tag if you want fully reproducible provisioning.
# ---------------------------------------------------------------------------
Write-Host "Downloading MQL5-ZeroMQ library..."
$zmqZip = "C:\OEM\mql5-zeromq.zip"
$zmqExtract = "C:\OEM\mql5-zeromq"
Invoke-WebRequest -Uri "https://github.com/ding9736/MQL5-ZeroMQ/archive/refs/heads/main.zip" -OutFile $zmqZip
Expand-Archive -Path $zmqZip -DestinationPath $zmqExtract -Force

$zmqRoot = Get-ChildItem $zmqExtract | Select-Object -First 1

# The repo's ZeroMQ.mqh (#include <ZeroMQ/ZeroMQ.mqh> from the EA) lives at
# the repo root and itself does #include "Core/Whatever.mqh" relative to
# its own folder -- so both need to land together under Include\ZeroMQ\.
$zmqIncludeDest = Join-Path $IncludeDir "ZeroMQ"
New-Item -ItemType Directory -Force -Path $zmqIncludeDest | Out-Null
Copy-Item -Path (Join-Path $zmqRoot.FullName "ZeroMQ.mqh") -Destination $zmqIncludeDest -Force
Copy-Item -Path (Join-Path $zmqRoot.FullName "Core") -Destination $zmqIncludeDest -Recurse -Force
Copy-Item -Path (Join-Path $zmqRoot.FullName "Libraries\*.dll") -Destination $LibrariesDir -Force

# ---------------------------------------------------------------------------
# 3. Drop in the EA source + default settings preset.
# ---------------------------------------------------------------------------
Copy-Item -Path "C:\OEM\TradingViewZeroMQExecutor.mq5" -Destination $ExpertsDir -Force
$presetsDir = Join-Path $MqlDir "Presets"
New-Item -ItemType Directory -Force -Path $presetsDir | Out-Null
Copy-Item -Path "C:\OEM\TradingViewZeroMQExecutor.set" -Destination (Join-Path $presetsDir "TradingViewZeroMQExecutor.set") -Force

# ---------------------------------------------------------------------------
# 4. Compile the EA headlessly via MetaEditor.
# ---------------------------------------------------------------------------
Write-Host "Compiling EA..."
$metaEditor = Join-Path $InstallDir "metaeditor64.exe"
Start-Process -FilePath $metaEditor -ArgumentList "/compile:`"$ExpertsDir\TradingViewZeroMQExecutor.mq5`"", "/log:`"C:\OEM\compile.log`"" -Wait

# ---------------------------------------------------------------------------
# 5. Startup config: enable Algo Trading + DLL imports, auto-attach the EA.
#    Broker login/password/server come from environment variables so no
#    credentials are ever baked into this repo or the VM image.
# ---------------------------------------------------------------------------
$mt5Login    = $env:MT5_LOGIN
$mt5Password = $env:MT5_PASSWORD
$mt5Server   = $env:MT5_SERVER
$mt5Symbol   = if ($env:MT5_SYMBOL) { $env:MT5_SYMBOL } else { "EURUSD" }

$configPath = Join-Path $ConfigDir "startup.ini"
@"
[Common]
Login=$mt5Login
Password=$mt5Password
Server=$mt5Server

[Experts]
AllowLiveTrading=1
AllowDllImport=1
Enabled=1

[StartUp]
Expert=TradingViewZeroMQExecutor
Symbol=$mt5Symbol
Period=M1
"@ | Out-File -FilePath $configPath -Encoding ascii

# ---------------------------------------------------------------------------
# 6. Launch on every login, in portable mode (keeps MQL5 data under
#    C:\MT5\MQL5 instead of a randomly-hashed AppData folder).
# ---------------------------------------------------------------------------
$startupFolder = [Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path $startupFolder "MT5.lnk"
$wshell = New-Object -ComObject WScript.Shell
$shortcut = $wshell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = Join-Path $InstallDir "terminal64.exe"
$shortcut.Arguments = "/portable /config:`"$configPath`""
$shortcut.WorkingDirectory = $InstallDir
$shortcut.Save()

Write-Host "Launching MT5 for the first time..."
Start-Process -FilePath (Join-Path $InstallDir "terminal64.exe") -ArgumentList "/portable", "/config:`"$configPath`""

Write-Host "Provisioning complete."
