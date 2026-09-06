from fastapi.testclient import TestClient
from app.main import app
from app.api.v1.endpoints.auth import _failed_login_attempts

client = TestClient(app)

def test_security_headers_present():
    response = client.get("/api/v1/health")
    assert response.status_code == 200
    assert response.headers["X-Content-Type-Options"] == "nosniff"
    assert response.headers["X-Frame-Options"] == "DENY"
    assert response.headers["X-XSS-Protection"] == "1; mode=block"
    assert response.headers["Referrer-Policy"] == "strict-origin-when-cross-origin"

def test_login_rate_limiting():
    _failed_login_attempts.clear()
    target_email = "ratelimit-test@simtack.com"

    # Make 5 failed attempts (the limit)
    for _ in range(5):
        resp = client.post(
            "/api/v1/auth/login",
            data={"username": target_email, "password": "WrongPassword1"}
        )
        assert resp.status_code == 401

    # 6th attempt should be blocked with 429 Too Many Requests
    blocked_resp = client.post(
        "/api/v1/auth/login",
        data={"username": target_email, "password": "WrongPassword1"}
    )
    assert blocked_resp.status_code == 429
    assert "Too many failed login attempts" in blocked_resp.json()["detail"]

    _failed_login_attempts.clear()
