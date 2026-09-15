import unittest
from fastapi.testclient import TestClient
from app.main import app

class TestAPIEndpoints(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(app)

    def test_root_endpoint(self):
        response = self.client.get("/")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIn("service", data)
        self.assertIn("version", data)

    def test_health_endpoint(self):
        response = self.client.get("/api/v1/health")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data["status"], "alive")

    def test_oversized_request_returns_payload_too_large(self):
        response = self.client.get(
            "/api/v1/health",
            headers={"content-length": str(10 * 1024 * 1024 + 1)},
        )
        self.assertEqual(response.status_code, 413)

if __name__ == "__main__":
    unittest.main()
