"""In-memory session registry.

One entry per connected user. Entries are created on connect and must be
removed on disconnect: this map is the only per-user state that outlives a
request, so a missed removal is a leak that grows for the life of the process.
"""

import time


class SessionRegistry:
    def __init__(self):
        self._by_user = {}

    def on_connect(self, user_id, transport):
        self._by_user[user_id] = {
            "transport": transport,
            "connected_at": time.monotonic(),
            "pending": [],
        }

    def on_disconnect(self, user_id):
        session = self._by_user.pop(user_id, None)
        if session is not None:
            session["transport"].close()

    def get(self, user_id):
        return self._by_user.get(user_id)

    def count(self):
        return len(self._by_user)
