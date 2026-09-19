"""Request handlers.

Everything in `payload` came from the client and is untrusted. Prices come
from the catalog, never from the request; quantities are bounded ints.
"""

import math

from app.cache import TtlCache
from app.sessions import SessionRegistry
from app.store import OrderStore

MAX_QUANTITY = 100

catalog_cache = TtlCache()
sessions = SessionRegistry()


def _lookup_price(catalog, sku):
    cached = catalog_cache.get(sku)
    if cached is not None:
        return cached
    price = catalog.price_for(sku)
    if price is not None:
        catalog_cache.put(sku, price)
    return price


def _parse_quantity(raw):
    if isinstance(raw, bool) or not isinstance(raw, int):
        return None
    if raw < 1 or raw > MAX_QUANTITY:
        return None
    return raw


def place_order(store: OrderStore, catalog, user_id, payload):
    sku = payload.get("sku")
    if not isinstance(sku, str) or not sku:
        return {"ok": False, "error": "bad sku"}
    quantity = _parse_quantity(payload.get("quantity"))
    if quantity is None:
        return {"ok": False, "error": "bad quantity"}
    unit_price = _lookup_price(catalog, sku)
    if unit_price is None or not math.isfinite(unit_price):
        return {"ok": False, "error": "unknown sku"}

    order = {
        "id": payload.get("client_order_id") or f"{user_id}-{sku}",
        "sku": sku,
        "quantity": quantity,
        "total": unit_price * quantity,
    }
    store.save(user_id, order)
    return {"ok": True, "order": order}


def connect(user_id, transport):
    sessions.on_connect(user_id, transport)


def disconnect(user_id):
    sessions.on_disconnect(user_id)
