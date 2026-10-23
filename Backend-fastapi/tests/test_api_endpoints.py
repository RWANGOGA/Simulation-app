import json
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

    def test_intake_still_accepts_a_client_that_sends_spo2(self):
        """An installed phone cannot be recalled, so the old intake payload has to
        keep working after SpO2 leaves the model.

        The field is dropped, not rejected: a 422 on a device that is still
        measuring would be a regression in the patient's intake flow, and the
        number must not be rewarded with priority or echoed back as if the
        server had an oxygen saturation to report.
        """
        body = {
            "body_region": "Chest / Heart",
            "pain_type": "crushing",
            "severity": 8,
            "heart_rate": 118.0,
        }
        legacy = self.client.post("/api/v1/triage/", json={**body, "spo2": 88.0})
        self.assertEqual(legacy.status_code, 201, legacy.text)
        current = self.client.post("/api/v1/triage/", json=body)
        self.assertEqual(current.status_code, 201, current.text)

        data = legacy.json()
        self.assertNotIn("spo2", data)
        twin = current.json()
        self.assertEqual(data["risk_score"], twin["risk_score"])
        self.assertNotIn("SpO2", data["shap_explanation"] or "")

        # And the retirement is real in the published contract, not just in the
        # response builder: the word does not appear anywhere a client could read
        # it as an offered field. (The document is served under the API prefix,
        # and only outside production - see app/main.py.)
        document = self.client.get("/api/v1/openapi.json").json()
        schemas = json.dumps(document["components"]["schemas"])
        self.assertIn("body_region", schemas)  # the triage models are in here
        self.assertNotIn("spo2", schemas)

if __name__ == "__main__":
    unittest.main()
