# Provisions MT5 + the ZeroMQ EA inside the dockur/windows VM.
#
# NOTE ON CONFIDENCE: steps 1-2 were run live twice against a real
# dockur/windows instance (Jake's Unraid box, 2026-09-13) and fixed up
# based on what actually happened:
#   - mt5setup.exe's /auto flag does NOT make it fully silent -- it still
#     shows a license-agreement screen and a finish screen that each need
#     a click. First fix (tracking Start-Process's PID) was WRONG and
#     confirmed broken on the second live run: under UAC elevation that
#     PID is the non-elevated launcher stub, which exits as soon as it
#     hands off to the real installer, so the script sailed past the
#     dialog without clicking it while the dialog sat there waiting. Now
#     polls for the setup window by title and for terminal64.exe's
#     existence instead -- this second approach has NOT itself had a full
#     clean live run yet, only the folder-structure fix below has been
#     confirmed working end to end.
#   - This all assumes install.bat runs elevated/as SYSTEM already (dockur/
#     windows' normal first-logon context) so no UAC *consent* prompt is
#     in the way -- SendKeys cannot click that (secure desktop). Every
#     live test run here hit that consent prompt because it was run
#     manually from a non-elevated session, which is not representative
#     of production -- if this hangs for real users, check for a stuck
#     UAC prompt via the noVNC/RDP console first.
#   - The ding9736/MQL5-ZeroMQ repo's actual layout is Core/*.mqh +
#     ZeroMQ.mqh at the repo root (the library's own README describes an
#     older "ZeroMQ folder" layout that no longer matches) -- fixed below
#     and CONFIRMED on the second live run (verified files landed at
#     C:\MT5\MQL5\Include\ZeroMQ\ZeroMQ.mqh and \Core\*.mqh).
#   - The installer's "Finish" screen auto-launches its own non-portable
#     terminal64 (using %AppData% instead of portable mode) and opens a
#     browser to an MQL5.com registration page -- confirmed live. The
#     stray terminal64 is killed below before our own portable launch;
#     the browser tab is harmless and left alone.
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
Start-Process -FilePath $mt5Setup -ArgumentList "/auto", "/dir=`"$InstallDir`""

# /auto still shows a license-agreement screen and a finish screen that
# each need a click (confirmed live). Poll for the setup window BY TITLE
# rather than tracking Start-Process's returned PID: under UAC elevation
# that PID is the non-elevated launcher stub, which exits as soon as it
# hands off to the real (elevated) installer process, so HasExited
# becomes true almost immediately and the loop would exit having clicked
# nothing (confirmed live -- the script sailed past this step while the
# real dialog sat waiting on screen). Detect real completion via
# terminal64.exe existing instead of any process handle.
#
# This assumes install.bat itself runs elevated/as SYSTEM (dockur/windows'
# normal first-logon provisioning context) so no UAC consent prompt is in
# the way -- SendKeys cannot click that dialog (it runs on the secure
# desktop). If this hangs, check the noVNC/RDP console for a stuck UAC
# prompt.
$wshell = New-Object -ComObject WScript.Shell
$terminalExe = Join-Path $InstallDir "terminal64.exe"
$deadline = (Get-Date).AddMinutes(5)
while (-not (Test-Path $terminalExe) -and (Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 2
    if ($wshell.AppActivate("MetaTrader 5 Setup")) {
        Start-Sleep -Milliseconds 500
        $wshell.SendKeys("{ENTER}")
    }
}
if (-not (Test-Path $terminalExe)) {
    throw "MT5 installer did not finish within 5 minutes -- check the noVNC/RDP console for a stuck dialog."
}
Start-Sleep -Seconds 3

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
