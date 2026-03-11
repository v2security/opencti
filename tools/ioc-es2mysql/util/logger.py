"""util.logger — centralised logging configuration.

Every module obtains its logger via ``get_logger(__name__)``.  Each logger:
  - writes to *stderr* with a uniform timestamp / level / name format,
  - has ``propagate = False`` to prevent duplicate lines from the root logger,
  - is created with exactly one handler (idempotent on repeated calls).

The root logger is configured once (on first ``get_logger`` call) to capture
output from third-party libraries (e.g. pycti) at WARNING level and above,
using the same format.

Usage::

    from util.logger import get_logger
    log = get_logger(__name__)
    log.info("Processing batch of %d items.", count)
"""

from __future__ import annotations

import logging
import sys

_FORMATTER = logging.Formatter(
    fmt="%(asctime)s  %(levelname)-8s  [%(name)s]  %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)


def _setup_root_once() -> None:
    """Configure the root logger exactly once.

    Clears any handlers that third-party libraries (pycti calls
    ``logging.basicConfig``) may have attached, replaces them with a
    single stderr handler using our standard format, and sets the root
    level to WARNING so only important third-party messages appear.
    """
    root = logging.getLogger()
    if getattr(root, "_ioc_configured", False):
        return
    root.handlers.clear()
    handler = logging.StreamHandler(sys.stderr)
    handler.setFormatter(_FORMATTER)
    root.addHandler(handler)
    root.setLevel(logging.WARNING)
    root._ioc_configured = True  # type: ignore[attr-defined]


def get_logger(name: str, level: str = "INFO") -> logging.Logger:
    """Return a named logger writing to stderr with the project-wide format.

    Safe to call multiple times with the same *name* — the handler is
    added only once and ``propagate`` is always set to ``False``.
    """
    _setup_root_once()
    logger = logging.getLogger(name)

    if not logger.handlers:
        handler = logging.StreamHandler(sys.stderr)
        handler.setFormatter(_FORMATTER)
        logger.addHandler(handler)

    logger.propagate = False
    logger.setLevel(getattr(logging, level, logging.INFO))
    return logger
