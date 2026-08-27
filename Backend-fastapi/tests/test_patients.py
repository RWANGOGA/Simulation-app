from fastapi.testclient import TestClient
from app.main import app
from tests.conftest import doctor_headers

client=TestClient(app)

def test_get_patient_requires_auth():
    #No token should give 401
    response = client.get("/api/v1/patients/P-ANON")
    assert response.status_code == 401

def test_get_patient_with_valid_token():
    #a valid token procceds beyond the auth gate
    headers = doctor_headers(client)
    response = client.get("/api/v1/patients/P-ANON", headers=headers)    
    assert response.status_code in (200, 404)