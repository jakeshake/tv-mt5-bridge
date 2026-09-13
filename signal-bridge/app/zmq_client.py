"""ZeroMQ PUSH socket wrapper.

Pattern: this service PUSHes, the MT5 EA PULLs and BINDs. That way MT5 can
restart without breaking this side's connection.
"""
import json
import logging
from datetime import datetime

import zmq

from . import config

logger = logging.getLogger(__name__)

_context = zmq.Context()
_socket = _context.socket(zmq.PUSH)
_connected = False

ADDRESS = f"tcp://{config.ZMQ_HOST}:{config.ZMQ_PORT}"


def connect():
    global _connected
    try:
        _socket.setsockopt(zmq.LINGER, 1000)
        _socket.setsockopt(zmq.SNDHWM, 100)
        _socket.setsockopt(zmq.SNDTIMEO, 1000)
        _socket.connect(ADDRESS)
        _connected = True
        logger.info(f"ZeroMQ PUSH socket connected to {ADDRESS}")
        return True
    except Exception as exc:
        logger.error(f"ZeroMQ connection failed: {exc}")
        _connected = False
        return False


def is_connected():
    return _connected


def send(signal_data):
    """Returns (success, latency_ms)."""
    start = datetime.now()
    try:
        message = json.dumps(signal_data)
        _socket.send_string(message, zmq.NOBLOCK)
        latency = (datetime.now() - start).total_seconds() * 1000
        logger.info(f"Signal pushed to MT5 in {latency:.3f}ms")
        return True, latency
    except zmq.Again:
        logger.warning("ZMQ send would block -- MT5 may not be connected or buffer is full")
        return False, 0
    except zmq.ZMQError as exc:
        logger.error(f"ZMQ error: {exc}")
        return False, 0
