"""Parses TradingView alert bodies into a plain dict.

TradingView alerts are free-text. This project's convention is a flat
`key=value,key2=value2` string (also accepts a JSON object body), e.g.:

    signal=long,symbol=EURUSD,qty=100000,entry_price=1.0850,
    sl_price=1.0800,tp_price=1.0950,secret=YOUR_SECRET

Values are type-converted (int/float/bool) where they parse cleanly;
everything else stays a string. Unknown keys are preserved as-is and
simply ignored downstream -- this is what lets an "advanced" alert format
(e.g. one with extra strategy-specific fields) reuse this same parser
without any changes here.
"""
import json
import re


def parse_alert(raw_data):
    if isinstance(raw_data, bytes):
        raw_data = raw_data.decode("utf-8")

    raw_data = raw_data.strip()

    if raw_data.startswith("{"):
        try:
            return json.loads(raw_data)
        except json.JSONDecodeError:
            pass

    result = {}
    pairs = re.split(r",(?=\w+=)", raw_data)

    for pair in pairs:
        pair = pair.strip()
        if "=" not in pair:
            continue
        key, value = pair.split("=", 1)
        key = key.strip().lower()
        value = value.strip()
        result[key] = _convert(value)

    return result


def _convert(value):
    try:
        if "." in value:
            return float(value)
        return int(value)
    except ValueError:
        pass

    low = value.lower()
    if low == "true":
        return True
    if low == "false":
        return False
    return value
