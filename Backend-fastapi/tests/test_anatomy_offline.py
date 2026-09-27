import unittest
from unittest.mock import patch
from fastapi.testclient import TestClient

from app.main import app


class TestAnatomyOffline(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(app)

    def test_list_regions_returns_all_34_regions(self):
        response = self.client.get("/api/v1/anatomy/regions")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIn("regions", data)
        regions = data["regions"]
        self.assertEqual(len(regions), 34)

        # Check key regions exist
        region_names = {r["region"] for r in regions}
        self.assertIn("Chest / Heart", region_names)
        self.assertIn("Neck", region_names)
        self.assertIn("Left Shin / Calf", region_names)
        self.assertIn("Right Foot", region_names)

    def test_anatomy_status_endpoint(self):
        response = self.client.get("/api/v1/anatomy/status")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertTrue(data["kb_loaded"])
        self.assertIn("llm_configured", data)

    def test_ask_endpoint_offline_fallback(self):
        """Simulate offline scenario by patching summarize_with_llm to return None."""
        with patch("app.api.v1.endpoints.anatomy.summarize_with_llm", return_value=None):
            payload = {
                "region": "Chest / Heart",
                "complaint": "sharp crushing pain when breathing",
                "top_k": 3,
            }
            response = self.client.post("/api/v1/anatomy/ask", json=payload)
            self.assertEqual(response.status_code, 200)
            data = response.json()

            self.assertFalse(data["llm_used"])
            self.assertEqual(data["region"], "Chest / Heart")
            self.assertIn("summary", data)
            self.assertIn("structures", data)
            self.assertIn("likely_conditions", data)
            self.assertIn("red_flags", data)
            self.assertIn("disclaimer", data)
            self.assertTrue(len(data["sources"]) > 0)
            self.assertTrue(len(data["citations"]) > 0)

    def test_ask_endpoint_missing_region_and_complaint(self):
        response = self.client.post("/api/v1/anatomy/ask", json={})
        self.assertEqual(response.status_code, 400)
        self.assertIn("Provide at least a region or a complaint", response.json()["detail"])

    def test_clear_conversation_endpoint(self):
        response = self.client.post("/api/v1/anatomy/clear?conversation_id=test_conv_123")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["cleared"], "test_conv_123")


if __name__ == "__main__":
    unittest.main()
