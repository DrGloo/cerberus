"""Order persistence with bounded retries.

`save` is the only writer. Callers pass the owning user first so a mixed-up
argument order fails loudly at the type check instead of writing an order
under the wrong user.
"""

import logging
import time

log = logging.getLogger(__name__)

MAX_ATTEMPTS = 3
RETRY_DELAY_SECONDS = 0.2


class StoreUnavailable(Exception):
    pass


class OrderStore:
    def __init__(self, backend):
        self._backend = backend

    def save(self, user_id, order):
        if not isinstance(user_id, int):
            raise TypeError("user_id must be an int")
        last_error = None
        for attempt in range(1, MAX_ATTEMPTS + 1):
            try:
                self._backend.write(f"orders/{user_id}/{order['id']}", order)
                return True
            except IOError as err:
                last_error = err
                log.warning(
                    "order save failed user=%s order=%s attempt=%s/%s: %s",
                    user_id, order["id"], attempt, MAX_ATTEMPTS, err,
                )
                time.sleep(RETRY_DELAY_SECONDS)
        raise StoreUnavailable(f"order {order['id']} not saved") from last_error

    def load(self, user_id, order_id):
        return self._backend.read(f"orders/{user_id}/{order_id}")
