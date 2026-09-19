"""Runtime configuration, read from the environment.

Nothing secret lives in this file. Tokens and URLs come from the environment
so a checkout never contains a credential.
"""

import os

BACKEND_URL = os.environ.get("ORDERS_BACKEND_URL", "http://localhost:8080")
BACKEND_TOKEN = os.environ.get("ORDERS_BACKEND_TOKEN", "")
