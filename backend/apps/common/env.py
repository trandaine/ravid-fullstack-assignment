"""Typed environment variable helpers."""

from __future__ import annotations

import os
from typing import overload


@overload
def env(key: str) -> str | None: ...


@overload
def env(key: str, default: str) -> str: ...


def env(key: str, default: str | None = None) -> str | None:
    """Return the value of key from os.environ, or default."""
    return os.environ.get(key, default)


def env_bool(key: str, default: bool = False) -> bool:
    """Return boolean value of key."""
    raw = os.environ.get(key)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def env_int(key: str, default: int = 0) -> int:
    """Return integer value of key, or default if absent/invalid."""
    raw = os.environ.get(key)
    if raw is None:
        return default
    try:
        return int(raw.strip())
    except ValueError:
        return default


def env_list(key: str, default: str = "") -> list[str]:
    """Return list of strings from a comma-separated env var."""
    raw = os.environ.get(key, default)
    return [item.strip() for item in raw.split(",") if item.strip()]
