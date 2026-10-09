import json
import os
import stat

from anios_reddit.settings import Settings


def test_round_trip_and_private_permissions(tmp_path):
    path = tmp_path / "cfg" / "config.json"
    s = Settings(client_id="abcdef1234", theme="light", last_sort="new")
    s.save(path)
    loaded = Settings.load(path)
    assert loaded == s
    assert stat.S_IMODE(os.stat(path).st_mode) == 0o600


def test_missing_or_broken_file_gives_defaults(tmp_path):
    assert Settings.load(tmp_path / "none.json").client_id == ""
    broken = tmp_path / "bad.json"
    broken.write_text("{not json", encoding="utf-8")
    assert Settings.load(broken).client_id == ""


def test_invalid_values_are_normalised(tmp_path):
    path = tmp_path / "c.json"
    path.write_text(json.dumps({"theme": "neon", "subreddits": ["linux"], "unknown": 1}), encoding="utf-8")
    s = Settings.load(path)
    assert s.theme == "dark"
    assert not hasattr(s, "subreddits")  # cấu hình cũ có danh sách subreddit vẫn đọc được
