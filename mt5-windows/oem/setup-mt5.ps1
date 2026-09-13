# Provisions MT5 + the ZeroMQ EA inside the dockur/windows VM.
#
# NOTE ON CONFIDENCE: this script has NOT been run end-to-end against a
# real dockur/windows instance from the environment that wrote it (no
# access to a Windows/KVM host during authoring). The MT5 terminal
# silent-install flags and the [Experts]/[StartUp] ini keys below match
# documented MetaTrader 5 "configuration at start" conventions, but you
# should watch provision.log on first boot and verify Algo Trading /
# DLL imports actually end up enabled (Tools > Options > Expert Advisors
# inside the terminal) before trusting this unattended. See
# docs/mt5-ea-setup.md for the manual fallback steps.

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
Start-Process -FilePath $mt5Setup -ArgumentList "/auto", "/dir=`"$InstallDir`"" -Wait

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
Copy-Item -Path (Join-Path $zmqRoot.FullName "Include\ZeroMQ") -Destination $IncludeDir -Recurse -Force
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
