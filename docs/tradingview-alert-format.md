# TradingView Alert Format

Set your TradingView alert's "Message" field to a flat `key=value,...`
string (a JSON object body also works, with the same keys).

## Required for every alert

| Field | Meaning |
|---|---|
| `signal` | One of the signal types below |
| `symbol` | Instrument symbol, e.g. `EURUSD` |
| `secret` | Must match the `WEBHOOK_SECRET` you configured |

## Entries: `signal=long` / `short` / `buy` / `sell`

| Field | Meaning |
|---|---|
| `qty` | Size in base-currency units (e.g. `100000` = 1.0 standard lot). Alternatively send `size` directly in lots. |
| `entry_price` | Price at signal time, used to convert `sl_price`/`tp_price` into pip distances |
| `sl_price`, `tp_price` | Absolute stop-loss / take-profit prices. Alternatively send `sl_pips`/`tp_pips` directly. |
| `comment` | Optional; tags the trade in MT5 |

```
signal=long,symbol=EURUSD,qty=100000,entry_price=1.0850,sl_price=1.0800,tp_price=1.0950,secret=YOUR_SECRET
```

## Exits

`signal=closelong` / `closeshort` / `close` / `closealllong` / `closeallshort`
/ `closeall` / `exitlong` / `exitshort` / `exit`

```
signal=closelong,symbol=EURUSD,secret=YOUR_SECRET
```

## Modify an open position's SL/TP

```
signal=modify,symbol=EURUSD,sl_price=1.0820,tp_price=1.0980,secret=YOUR_SECRET
```

## Testing without TradingView

```bash
curl -X POST https://your-tunnel-hostname/webhook \
  -d "signal=long,symbol=EURUSD,qty=100000,entry_price=1.0850,sl_price=1.0800,tp_price=1.0950,secret=YOUR_SECRET"
```

Or use `GET /test` on signal-bridge for a self-describing summary of
supported signals, and `POST /test` (optionally `?send=1`) to dry-run the
parser without touching the real `/webhook` route.

## A note on extending this

This schema is intentionally minimal. If your own strategy needs extra
fields (e.g. zone IDs, resting limit orders, regime tags), the parser
already passes unknown key=value fields through untouched -- you only need
to add a handler in `signal-bridge/app/translate.py` via
`translate.register_handler("your_signal_type", your_function)` rather
than modifying the generic path.
