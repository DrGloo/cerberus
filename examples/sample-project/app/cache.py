"""Bounded TTL cache for catalog lookups."""

import time

DEFAULT_TTL_SECONDS = 60
MAX_ENTRIES = 1000


class TtlCache:
    def __init__(self, ttl=DEFAULT_TTL_SECONDS, max_entries=MAX_ENTRIES):
        self._ttl = ttl
        self._max = max_entries
        self._entries = {}

    def get(self, key):
        entry = self._entries.get(key)
        if entry is None:
            return None
        value, expires_at = entry
        if expires_at < time.monotonic():
            del self._entries[key]
            return None
        return value

    def put(self, key, value):
        if len(self._entries) >= self._max:
            self._evict_oldest()
        self._entries[key] = (value, time.monotonic() + self._ttl)

    def _evict_oldest(self):
        oldest = min(self._entries, key=lambda k: self._entries[k][1])
        del self._entries[oldest]
