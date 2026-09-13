"""All runtime configuration, sourced from environment variables.

Nothing here should ever be a hardcoded LAN IP, port, or secret -- this
container is meant to run unmodified on any trader's own network.
"""
import os


def _env_bool(name, default):
    val = os.environ.get(name)
    if val is None:
        return default
    return val.strip().lower() in ("1", "true", "yes", "on")


# Flask
FLASK_HOST = os.environ.get("FLASK_HOST", "0.0.0.0")
FLASK_PORT = int(os.environ.get("FLASK_PORT", "5000"))

# ZeroMQ -- the MT5 EA binds a PULL socket and listens; this service
# connects to it as a PUSH socket. ZMQ_HOST must point at wherever the
# mt5-windows container/VM is reachable on your network.
ZMQ_HOST = os.environ.get("ZMQ_HOST")
ZMQ_PORT = int(os.environ.get("ZMQ_PORT", "5555"))

# Shared-secret auth. TradingView alerts can only send a raw text body (no
# custom headers), so the secret travels as a field in the alert payload
# itself: `...,secret=<value>`. REQUIRED once this is exposed to the
# internet -- leaving it unset disables the check, which is only meant for
# local testing before you put a tunnel in front of this.
WEBHOOK_SECRET = os.environ.get("WEBHOOK_SECRET", "")
REQUIRE_SECRET = _env_bool("REQUIRE_WEBHOOK_SECRET", True)

# Logging
LOG_DIR = os.environ.get("LOG_DIR", "/logs")
LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO")

# Units of base currency per 1.0 lot, keyed by symbol. Standard forex lot =
# 100,000 units. Add entries here for non-forex instruments (crypto,
# indices, metals) you trade through this bridge -- they don't use the
# 100,000 convention and will silently mis-size if left on the default.
UNITS_PER_LOT = {
    "DEFAULT_FX": 100000,
}


def validate():
    """Fail fast on startup instead of silently degrading."""
    problems = []
    if not ZMQ_HOST:
        problems.append(
            "ZMQ_HOST is not set -- point it at the host/IP running your "
            "MT5 EA (the mt5-windows container's address)."
        )
    if REQUIRE_SECRET and not WEBHOOK_SECRET:
        problems.append(
            "WEBHOOK_SECRET is not set but REQUIRE_WEBHOOK_SECRET is true. "
            "Set WEBHOOK_SECRET to a long random value, or explicitly set "
            "REQUIRE_WEBHOOK_SECRET=false if you understand the risk "
            "(anyone who finds your webhook URL can trigger live trades)."
        )
    return problems
