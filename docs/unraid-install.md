# Installing on Unraid via Community Applications

This repo ships Unraid template XML files in `unraid-templates/` so the
three containers can be added from the **Apps** tab instead of hand-writing
`docker run` commands.

## 1. Add this repo as a template source

1. In Unraid, go to **Apps > Settings** (gear icon, top right of the Apps
   tab).
2. Under **Template repositories**, add:
   ```
   https://github.com/<your-github-username>/tv-mt5-bridge
   ```
3. Save. The apps below should now show up under **Apps > search "tv-mt5"**.

## 2. Install the three containers

Install in this order so `mt5-windows` exists before `signal-bridge` needs
to reach it:

1. **mt5-windows** -- fill in `PASSWORD` (the Windows account, not your
   broker), `MT5_LOGIN`/`MT5_PASSWORD`/`MT5_SERVER`/`MT5_SYMBOL`, and
   confirm `RAM_SIZE`/`CPU_CORES`/`DISK_SIZE` fit your hardware. Requires
   `/dev/kvm` -- enable virtualization in your BIOS if apply/start fails.
2. **signal-bridge** -- set `ZMQ_HOST` to the mt5-windows container's name
   or IP, and `WEBHOOK_SECRET` to a long random value.
3. **cloudflared** -- set `TUNNEL_TOKEN` from
   [cloudflare-tunnel-setup.md](cloudflare-tunnel-setup.md).

## 3. Verify

- Open the mt5-windows WebUI (port 8006) to watch the desktop provision
  itself, per [mt5-ea-setup.md](mt5-ea-setup.md).
- `curl http://<unraid-ip>:5000/health` should return
  `{"status": "healthy", ...}`.
- Send a test alert per
  [tradingview-alert-format.md](tradingview-alert-format.md) and confirm it
  shows up in signal-bridge's log (Docker tab > signal-bridge > Logs).

If you'd rather run the whole stack from one `docker-compose.yml` instead of
three separate CA templates, Unraid's **Compose Manager** plugin (Community
Applications) can point directly at this repo's `docker-compose.yml`.
