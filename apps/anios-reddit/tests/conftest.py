import json
import os
import sys
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

FIXTURES = Path(__file__).parent / "fixtures"


def load_fixture(name: str):
    return json.loads((FIXTURES / name).read_text(encoding="utf-8"))


class FakeReddit:
    """Transport giả lập Reddit: ghi lại yêu cầu và trả về fixture theo đường dẫn."""

    def __init__(self):
        self.calls = []
        self.routes = {}
        self.token_ok = True
        self.fail_status = None
        self.fail_headers = {}

    def __call__(self, method, url, headers, body):
        self.calls.append((method, url, dict(headers), body))
        if self.fail_status and "access_token" not in url:
            return self.fail_status, "{}", self.fail_headers
        if "access_token" in url:
            if not self.token_ok:
                return 401, "{}", {}
            return 200, json.dumps({"access_token": "tok-test", "expires_in": 3600, "token_type": "bearer"}), {}
        if "after=" in url and "/r/unixporn/" in url:
            return 200, json.dumps(load_fixture("listing_next.json")), {}
        for needle, payload in self.routes.items():
            if needle in url:
                return 200, json.dumps(payload() if callable(payload) else payload), {}
        return 404, "{}", {}

    def requests_to(self, needle):
        return [c for c in self.calls if needle in c[1]]


def make_fake():
    fake = FakeReddit()
    fake.routes = {
        "/r/unixporn/": lambda: load_fixture("listing_hot.json"),
        "/comments/": lambda: load_fixture("comments.json"),
    }
    return fake
