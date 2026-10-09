import base64
import json
import urllib.parse

import pytest

from anios_reddit import api
from anios_reddit.api import RedditClient, RedditError, compact_number, make_user_agent, relative_time
from conftest import load_fixture, make_fake


def test_user_agent_follows_reddit_format():
    assert make_user_agent("kevin") == "linux:com.anios.reddit:0.1.0 (by /u/kevin)"
    assert make_user_agent("/u/kevin ") == "linux:com.anios.reddit:0.1.0 (by /u/kevin)"
    assert make_user_agent("") == "linux:com.anios.reddit:0.1.0 (by /u/anios-user)"


def test_empty_client_id_is_rejected():
    with pytest.raises(RedditError):
        RedditClient("   ")


def test_listing_parses_posts_and_cursor():
    page = api.parse_listing(load_fixture("listing_hot.json"))
    assert page.after == "t3_abc003"
    assert len(page.posts) == 4
    first = page.posts[0]
    assert first["stickied"] is True
    assert first["thumbnail"] == "https://preview.redd.it/example-1.png?width=1080&format=png&s=abc"  # đã giải mã &amp;
    assert first["permalink"].startswith("https://www.reddit.com/r/unixporn/comments/")
    assert first["scoreText"] == "2.5k"
    assert first["commentsText"] == "212"
    assert page.posts[2]["isSelf"] is False
    assert page.posts[2]["domain"] == "www.kernel.org"
    assert page.posts[3]["nsfw"] is True


def test_last_page_has_no_cursor():
    page = api.parse_listing(load_fixture("listing_next.json"))
    assert page.after is None


def test_comments_are_flattened_in_display_order_with_depth():
    children = load_fixture("comments.json")[1]["data"]["children"]
    rows = api.parse_comments(children)
    assert [r["id"] for r in rows] == ["c001", "c002", "c003", "c004"]
    assert [r["depth"] for r in rows] == [0, 1, 2, 0]
    assert rows[2]["isOp"] is True
    assert rows[0]["body"].startswith("Cảm ơn")


def test_comment_depth_and_limit_are_respected():
    children = load_fixture("comments.json")[1]["data"]["children"]
    assert [r["id"] for r in api.parse_comments(children, max_depth=2)] == ["c001", "c002", "c004"]
    assert len(api.parse_comments(children, limit=2)) == 2


def test_auth_uses_installed_client_grant_and_caches_token():
    fake = make_fake()
    now = [1000.0]
    client = RedditClient("abc123client", transport=fake, clock=lambda: now[0], device_id="dev" * 8)
    client.listing("linux", "hot")
    client.listing("linux", "hot", after="t3_abc003")
    token_calls = fake.requests_to("access_token")
    assert len(token_calls) == 1
    method, url, headers, body = token_calls[0]
    assert method == "POST"
    assert headers["Authorization"] == "Basic " + base64.b64encode(b"abc123client:").decode()
    assert b"grant_type=https%3A%2F%2Foauth.reddit.com%2Fgrants%2Finstalled_client" in body
    api_calls = fake.requests_to("oauth.reddit.com/r/linux")
    assert all(c[2]["Authorization"] == "bearer tok-test" for c in api_calls)
    assert all(c[2]["User-Agent"].startswith("linux:com.anios.reddit:") for c in api_calls)
    # Hết hạn: phải xin token mới
    now[0] += 4000
    client.listing("linux", "hot")
    assert len(fake.requests_to("access_token")) == 2


def test_listing_url_and_time_range():
    fake = make_fake()
    client = RedditClient("abc", transport=fake)
    client.listing("r/linux", "top", time_range="week")
    url = fake.requests_to("/r/linux/top")[0][1]
    assert "/r/linux/top?" in url and "t=week" in url and "limit=25" in url and "raw_json=1" in url
    client.listing("linux", "hot")
    assert "t" not in urllib.parse.parse_qs(urllib.parse.urlparse(fake.requests_to("/r/linux/hot")[0][1]).query)


def test_invalid_sort_raises():
    client = RedditClient("abc", transport=make_fake())
    with pytest.raises(RedditError):
        client.listing("linux", "bogus")


def test_search_requires_query_and_falls_back_to_relevance():
    fake = make_fake()
    client = RedditClient("abc", transport=fake)
    with pytest.raises(RedditError):
        client.search("   ")
    client.search("waydroid", sort="nonsense")
    url = fake.requests_to("/search")[0][1]
    assert "q=waydroid" in url and "sort=relevance" in url


def test_comments_request_returns_flat_rows():
    client = RedditClient("abc", transport=make_fake())
    rows = client.comments("abc001")
    assert len(rows) == 4


def test_forbidden_and_rate_limit_messages():
    fake = make_fake()
    client = RedditClient("abc", transport=fake)
    fake.fail_status = 403
    with pytest.raises(RedditError) as exc:
        client.listing("linux")
    assert "403" in str(exc.value)

    fake2 = make_fake()
    fake2.fail_status = 429
    fake2.fail_headers = {"X-Ratelimit-Reset": "42"}
    with pytest.raises(RedditError) as exc2:
        RedditClient("abc", transport=fake2).listing("linux")
    assert "42 giây" in str(exc2.value)


def test_unauthorized_clears_token_so_next_call_refreshes():
    fake = make_fake()
    client = RedditClient("abc", transport=fake)
    client.listing("linux")  # lấy token đầu tiên
    fake.calls.clear()
    fake.fail_status = 401  # API từ chối token đang dùng
    with pytest.raises(RedditError):
        client.listing("linux")
    fake.fail_status = None
    client.listing("linux")  # phải xin token mới trước khi gọi lại API
    assert len(fake.requests_to("access_token")) == 1


def test_bad_token_response_is_reported():
    fake = make_fake()
    fake.token_ok = False
    with pytest.raises(RedditError) as exc:
        RedditClient("abc", transport=fake).listing("linux")
    assert "client ID" in str(exc.value)


def test_non_json_response_is_reported():
    def bad(method, url, headers, body):
        if "access_token" in url:
            return 200, json.dumps({"access_token": "t"}), {}
        return 200, "<html>blocked</html>", {}

    with pytest.raises(RedditError):
        RedditClient("abc", transport=bad).listing("linux")


def test_compact_number_and_relative_time():
    assert compact_number(999) == "999"
    assert compact_number(1000) == "1k"
    assert compact_number(1250) == "1.2k"
    assert compact_number(2_000_000) == "2M"
    now = 1_000_000.0
    assert relative_time(now - 30, now) == "vừa xong"
    assert relative_time(now - 300, now) == "5 phút trước"
    assert relative_time(now - 3 * 3600, now) == "3 giờ trước"
    assert relative_time(now - 2 * 86400, now) == "2 ngày trước"
    assert relative_time(now - 400 * 86400, now) == "1 năm trước"
    assert relative_time(0, now) == ""
