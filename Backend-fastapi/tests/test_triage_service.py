import unittest
from app.schemas import TriageCreate
from app.services.triage_service import (
    compute_risk,
    risk_level,
    explain,
    _heart_rate_contribution
)

class TestTriageService(unittest.TestCase):
    def test_heart_rate_contribution(self):
        self.assertEqual(_heart_rate_contribution(None), 0.0)
        self.assertEqual(_heart_rate_contribution(72.0), 0.0)
        self.assertEqual(_heart_rate_contribution(105.0), 0.10)
        self.assertEqual(_heart_rate_contribution(130.0), 0.15)
        self.assertEqual(_heart_rate_contribution(45.0), 0.15)

    def test_compute_risk_high_risk_chest_pain(self):
        triage_data = TriageCreate(
            body_region="Chest",
            pain_type="crushing",
            severity=10,
            heart_rate=125.0
        )
        risk, contributions = compute_risk(triage_data)
        
        # 1.0 (severity) * 0.50 = 0.50
        # Chest = 0.40
        # crushing = 0.20
        # HR > 120 = 0.15
        # Total = 1.25 -> capped at 1.0
        self.assertEqual(risk, 1.0)
        self.assertEqual(risk_level(risk), "high")
        self.assertTrue(any(c["factor"] == "Severity 10/10" for c in contributions))
        self.assertTrue(any(c["factor"] == "Region: Chest" for c in contributions))

    def test_compute_risk_low_risk(self):
        triage_data = TriageCreate(
            body_region="Right Leg",
            pain_type="dull",
            severity=2,
            heart_rate=70.0
        )
        risk, contributions = compute_risk(triage_data)
        
        # Severity 2 = 0.10
        # Right Leg = 0.10
        # dull = 0.05
        # Total = 0.25
        self.assertEqual(risk, 0.25)
        self.assertEqual(risk_level(risk), "low")

    def test_risk_level_thresholds(self):
        self.assertEqual(risk_level(0.70), "high")
        self.assertEqual(risk_level(0.85), "high")
        self.assertEqual(risk_level(0.40), "medium")
        self.assertEqual(risk_level(0.69), "medium")
        self.assertEqual(risk_level(0.39), "low")
        self.assertEqual(risk_level(0.0), "low")

    def test_explain_json_formatting(self):
        contributions = [{"factor": "Severity 5/10", "shap": 0.25}]
        explanation = explain(contributions)
        self.assertIn("Severity 5/10", explanation)

if __name__ == "__main__":
    unittest.main()
