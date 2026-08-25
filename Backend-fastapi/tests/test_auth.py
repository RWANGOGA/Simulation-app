import pytest
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)

def test_login_success():
    response = client.post(
        "/api/v1/auth/login",
        data={"username": "doctor@simtack.com", "password": "Doctor123!"}
    )
    assert response.status_code == 200
    data = response.json()
    assert "access_token" in data
    assert data["token_type"] == "bearer"

def test_login_invalid_password():
    response = client.post(
        "/api/v1/auth/login",
        data={"username": "doctor@simtack.com", "password": "WrongPassword!"}
    )
    assert response.status_code == 401
    assert response.json()["detail"] == "Incorrect email or password"

def test_read_users_me_success():
    login_response = client.post(
        "/api/v1/auth/login",
        data={"username": "doctor@simtack.com", "password": "Doctor123!"}
    )
    token = login_response.json()["access_token"]
    
    headers = {"Authorization": f"Bearer {token}"}
    response = client.get("/api/v1/auth/me", headers=headers)
    
    assert response.status_code == 200
    data = response.json()
    assert data["email"] == "doctor@simtack.com"
