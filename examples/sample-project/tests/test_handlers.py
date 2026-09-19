from app import handlers


class FakeCatalog:
    def price_for(self, sku):
        return {"apple": 1.5, "pear": 2.0}.get(sku)


class FakeStore:
    def __init__(self):
        self.saved = []

    def save(self, user_id, order):
        self.saved.append((user_id, order))
        return True


def test_place_order_uses_catalog_price():
    store = FakeStore()
    result = handlers.place_order(store, FakeCatalog(), 7, {"sku": "apple", "quantity": 2})
    assert result["ok"] is True
    assert result["order"]["total"] == 3.0
    assert store.saved[0][0] == 7


def test_place_order_rejects_bad_quantity():
    result = handlers.place_order(FakeStore(), FakeCatalog(), 7, {"sku": "apple", "quantity": 0})
    assert result["ok"] is False
    result = handlers.place_order(FakeStore(), FakeCatalog(), 7, {"sku": "apple", "quantity": True})
    assert result["ok"] is False


def test_place_order_ignores_client_price():
    result = handlers.place_order(FakeStore(), FakeCatalog(), 7, {"sku": "pear", "quantity": 1, "price": 0.01})
    assert result["order"]["total"] == 2.0
