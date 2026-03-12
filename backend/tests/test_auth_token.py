from app.transport.websocket_server import tokens_match


def test_tokens_match_allows_when_server_token_is_not_configured() -> None:
    assert tokens_match(None, None)
    assert tokens_match("", "anything")


def test_tokens_match_rejects_missing_client_token_when_required() -> None:
    assert not tokens_match("secret", None)
    assert not tokens_match("secret", "")


def test_tokens_match_accepts_exact_match() -> None:
    assert tokens_match("secret", "secret")


def test_tokens_match_normalizes_whitespace() -> None:
    assert tokens_match(" secret ", "  secret")
