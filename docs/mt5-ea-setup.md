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

**Partially verified live** (2026-09-13, against a real dockur/windows
instance on Jake's Unraid box) -- steps 1-2 have real fixes behind them now,
steps 3-6 are still only documentation-reviewed. Two concrete things found
by actually running this:

- **`mt5setup.exe /auto` is not fully silent.** It still shows a
  license-agreement screen and a finish screen that each need a click. The
  script handles this with a SendKeys loop, but that loop depends on
  `install.bat` running elevated/as SYSTEM already (dockur/windows' normal
  first-logon context) -- SendKeys cannot dismiss an actual UAC *consent*
  prompt (that runs on the secure desktop). If provisioning seems to hang,
  open the noVNC viewer and check for a stuck UAC dialog first.
- **The ding9736/MQL5-ZeroMQ repo's layout** is `Core/*.mqh` + `ZeroMQ.mqh`
  at the repo root, not the `Include/ZeroMQ/` layout its own README
  describes -- confirmed and fixed; verified the files land at
  `C:\MT5\MQL5\Include\ZeroMQ\ZeroMQ.mqh` and `\Core\*.mqh`.

After first boot:

1. Open the noVNC viewer at `http://<host>:8006` to watch the Windows
   desktop directly.
2. Check `C:\OEM\provision.log` and `C:\OEM\compile.log` for errors.
3. Confirm in the terminal itself (**Tools > Options > Expert Advisors**)
   that "Allow Algo Trading" and "Allow DLL imports" are both checked, and
   that the EA shows a green face icon on its chart (not a red X).

### If you're troubleshooting manually via noVNC

The noVNC session's keyboard forwarding drops the Shift modifier for
typed/pasted keystrokes in at least this setup -- `:`, uppercase letters,
and other shifted characters can arrive as their unshifted equivalent (e.g.
`:` becomes `;`, `|` becomes `\`). PowerShell commands are case-insensitive
so lowercase-only commands still work, but avoid typing colons or pipes
directly; instead `cd \` to root then use relative paths, and use the
noVNC sidebar's clipboard panel (or open Chrome inside the VM and use
"Save As" / "Open in Terminal" to avoid typing paths at all) rather than
typing a full command with special characters at the console.

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
