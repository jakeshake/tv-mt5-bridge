# Architecture

```
TradingView alert
      |
      | HTTPS POST
      v
Cloudflare Tunnel (cloudflared container)
      |
      | HTTP POST /webhook  (LAN only, never exposed directly)
      v
signal-bridge (Flask)
      |  - checks the shared secret
      |  - parses key=value alert body
      |  - translates to an EA message (BUY/SELL/CLOSE*/MODIFY)
      |
      | ZeroMQ PUSH  (tcp://mt5-windows:5555)
      v
mt5-windows (dockur/windows VM)
      |
      | ZeroMQ PULL, inside the MT5 terminal
      v
TradingViewZeroMQExecutor.mq5 (Expert Advisor)
      |
      v
Real order placed on your MT5 broker account
```

## Why this shape

- **Cloudflare Tunnel, not port-forwarding**: gives a stable HTTPS URL
  without opening inbound ports on your router, and works behind CGNAT.
- **ZeroMQ PUSH/PULL, not HTTP, between signal-bridge and MT5**: MT5 binds
  and listens; signal-bridge connects to it. MT5 (or the whole Windows VM)
  can restart without signal-bridge needing to reconnect logic beyond normal
  ZMQ reconnection, and delivery is ~1-5ms on a local network.
- **signal-bridge is generic**: it only understands a small, documented
  alert schema (see `tradingview-alert-format.md`). Any TradingView strategy
  that emits that schema works, not just one specific Pine script.

## Latency

End-to-end from TradingView firing an alert to the EA receiving it is
dominated by TradingView's own alert delivery (seconds, not milliseconds) --
the signal-bridge -> MT5 leg itself is single-digit milliseconds on a local
network.
