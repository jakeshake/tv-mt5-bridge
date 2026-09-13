# MT5 + EA Setup (mt5-windows container)

The `mt5-windows` service runs [dockur/windows](https://github.com/dockur/windows),
which boots a real Windows VM via KVM/QEMU inside a container, then
auto-provisions it using the scripts in `mt5-windows/oem/`.

## Prerequisites

- A host with `/dev/kvm` available (Unraid: enable virtualization in BIOS;
  the same requirement as running Unraid's own VMs).
- Your own Windows 11 license. dockur/windows can install from Microsoft's
  public evaluation image, but you're responsible for licensing it for
  anything beyond evaluation use.
- Your MT5 broker login, password, and server name (from your broker, not
  from this project).

## What gets automated (`mt5-windows/oem/setup-mt5.ps1`)

1. Downloads and silently installs the generic MetaQuotes MT5 terminal to
   `C:\MT5` (portable mode, so all data lives under `C:\MT5\MQL5` instead of
   a hashed AppData folder).
2. Downloads the [ding9736/MQL5-ZeroMQ](https://github.com/ding9736/MQL5-ZeroMQ)
   library and places the headers/DLLs where the EA expects them.
3. Copies in `TradingViewZeroMQExecutor.mq5` and its default `.set` preset,
   then compiles the EA headlessly via MetaEditor.
4. Writes a startup config (`C:\MT5\config\startup.ini`) that enables Algo
   Trading + DLL imports and attaches the EA to a chart, using
   `MT5_LOGIN`/`MT5_PASSWORD`/`MT5_SERVER`/`MT5_SYMBOL` from your `.env`.
5. Creates a Startup-folder shortcut so MT5 launches automatically on every
   boot with that config.

**This has not been verified end-to-end on real hardware by anyone other
than through documentation review.** The MT5 terminal's silent-install flags
and the `[Experts]`/`[StartUp]` ini keys match MetaTrader 5's documented
"configuration at start" conventions, but terminal builds change. After
first boot:

1. Open the noVNC viewer at `http://<host>:8006` to watch the Windows
   desktop directly.
2. Check `C:\OEM\provision.log` and `C:\OEM\compile.log` for errors.
3. Confirm in the terminal itself (**Tools > Options > Expert Advisors**)
   that "Allow Algo Trading" and "Allow DLL imports" are both checked, and
   that the EA shows a green face icon on its chart (not a red X).

## Manual fallback

If the automated startup config doesn't take effect, do this once by hand
inside the VM (via the noVNC viewer or RDP on port 3389):

1. Open MT5, log into your broker account (Login/Password/Server).
2. **Tools > Options > Expert Advisors**: check "Allow Algo Trading" and
   "Allow DLL imports".
3. Open a chart for your symbol, drag `TradingViewZeroMQExecutor` from the
   Navigator's Expert Advisors list onto it, load
   `MQL5/Presets/TradingViewZeroMQExecutor.set` in the Inputs tab.
4. Confirm "Algo Trading" is toggled on in the toolbar.

## Networking

signal-bridge connects to `ZMQ_HOST:ZMQ_PORT` (default `mt5-windows:5555`).
With the default Docker bridge network in `docker-compose.yml`, compose's
built-in DNS resolves `mt5-windows` to the right container automatically --
no extra networking setup needed for a single-host deployment.
