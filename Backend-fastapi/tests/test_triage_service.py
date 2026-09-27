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

    def test_region_weights_all_categories(self):
        from app.services.triage_service import _region_weight
        self.assertEqual(_region_weight("Chest / Heart"), 0.40)
        self.assertEqual(_region_weight("Headache / Cranial"), 0.35)
        self.assertEqual(_region_weight("Neck"), 0.30)
        self.assertEqual(_region_weight("Abdomen (Upper)"), 0.25)
        self.assertEqual(_region_weight("Back Pain (Upper)"), 0.20)
        self.assertEqual(_region_weight("Left Arm / Shoulder"), 0.20)
        self.assertEqual(_region_weight("Left Wrist"), 0.20)
        self.assertEqual(_region_weight("Right Shoulder"), 0.15)
        self.assertEqual(_region_weight("Right Hand"), 0.15)
        self.assertEqual(_region_weight("Left Shin / Calf"), 0.10)
        self.assertEqual(_region_weight("Right Ankle"), 0.10)
        self.assertEqual(_region_weight("Hips / Groin"), 0.10)

    def test_spo2_and_bmi_contributions(self):
        from app.services.triage_service import _spo2_contribution, _bmi_contribution
        self.assertEqual(_spo2_contribution(None), 0.0)
        self.assertEqual(_spo2_contribution(98.0), 0.0)
        self.assertEqual(_spo2_contribution(94.0), 0.10)
        self.assertEqual(_spo2_contribution(89.0), 0.15)

        contrib, bmi = _bmi_contribution(None, 170.0)
        self.assertEqual(contrib, 0.0)
        self.assertIsNone(bmi)

        # BMI = 90 / (1.75^2) = 29.38 -> normal
        contrib, bmi = _bmi_contribution(90.0, 175.0)
        self.assertEqual(contrib, 0.0)

        # Obese BMI = 110 / (1.75^2) = 35.9 -> 0.05 bump
        contrib, bmi = _bmi_contribution(110.0, 175.0)
        self.assertEqual(contrib, 0.05)
        self.assertAlmostEqual(bmi, 35.9, places=1)

    def test_compute_risk_with_sibling_regions(self):
        triage_data = TriageCreate(
            body_region="Chest / Heart",
            pain_type="sharp",
            severity=7,
            heart_rate=110.0,
            spo2=93.0,
        )
        # Sibling region has classic cardiac radiation
        siblings = ["Left Arm / Shoulder"]
        risk, contributions = compute_risk(triage_data, sibling_regions=siblings)

        # Expect connectivity factor to be present with 0.25 (high concern) bump
        factors = [c["factor"] for c in contributions]
        self.assertTrue(any("Connected to reported Left Arm / Shoulder pain" in f for f in factors))
        self.assertGreaterEqual(risk, 0.70)
        self.assertEqual(risk_level(risk), "high")


if __name__ == "__main__":
    unittest.main()

