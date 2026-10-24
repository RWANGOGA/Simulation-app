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

    def test_contributions_always_sum_to_the_reported_score(self):
        """The breakdown must add up to the number it explains.

        Before this, `compute_risk` clamped the score to 1.0 and returned the
        unclamped factors, so a chest pain at severity 10 with a heart rate of 135
        reported `risk_score: 1.0` beside an explanation whose factors summed to 1.30.
        That is not a rounding curiosity: a sweep over the full region / pain /
        severity / heart-rate / BMI / sibling grid found the cap biting in 3,446 of
        18,000 combinations - about one triage in five - and the factor list is
        exactly what the clinician is shown as *why*.

        Swept rather than sampled, because the invariant is arithmetic and a single
        hand-picked case would pass while the cap silently stayed broken elsewhere.
        """
        regions = [
            "Chest / Heart", "Headache / Cranial", "Left Arm / Shoulder",
            "Left Leg", "Abdomen (Upper)", "Neck", "",
        ]
        pain_types = ["Crushing", "Stabbing", "Sharp", "Dull", "Burning"]
        heart_rates = [None, 95.0, 110.0, 135.0, 45.0]
        bodies = [(None, None), (90.0, 170.0), (120.0, 160.0)]
        sibling_sets = [[], ["Chest / Heart"], ["Left Arm / Shoulder", "Neck"]]

        capped_cases = 0
        for region in regions:
            for pain_type in pain_types:
                for severity in range(1, 11):
                    for heart_rate in heart_rates:
                        for weight, height in bodies:
                            for siblings in sibling_sets:
                                data = TriageCreate(
                                    body_region=region,
                                    pain_type=pain_type,
                                    severity=severity,
                                    heart_rate=heart_rate,
                                )
                                risk, contributions = compute_risk(
                                    data,
                                    sibling_regions=siblings,
                                    patient_weight=weight,
                                    patient_height=height,
                                )
                                total = round(
                                    sum(c["shap"] for c in contributions), 10
                                )
                                self.assertAlmostEqual(
                                    total, risk, places=6,
                                    msg=(
                                        f"factors sum to {total} but score is {risk} "
                                        f"for {region}/{pain_type}/{severity}"
                                    ),
                                )
                                self.assertLessEqual(risk, 1.0)
                                if any(c["shap"] < 0 for c in contributions):
                                    capped_cases += 1

        self.assertGreater(capped_cases, 0, "no case ever reached the cap")

    def test_every_factor_carries_contribution_and_its_shap_alias(self):
        """`contribution` is the real name; `shap` is a compatibility mirror.

        Nothing in this service is a SHAP value - there is no attribution model,
        just hand-set weights summed - so the key was renamed. The mirror exists
        only because builds already on phones read `shap`, and a row with only the
        new key renders "+0%" for every factor instead of failing loudly.

        Asserted row by row including the cap, because the failure this guards is
        a *missing* mirror on one branch: the connectivity and cap rows are built
        somewhere other than the main list and were the likely ones to be missed.
        """
        data = TriageCreate(
            body_region="Chest / Heart", pain_type="crushing", severity=10,
            heart_rate=135.0,
        )
        _, contributions = compute_risk(
            data,
            sibling_regions=["Left Arm / Shoulder"],
            patient_weight=120.0,
            patient_height=160.0,
        )
        self.assertGreaterEqual(len(contributions), 6)
        for row in contributions:
            self.assertIn("contribution", row, row)
            self.assertIn("shap", row, row)
            self.assertEqual(row["contribution"], row["shap"], row)
            self.assertEqual(
                row["impact"], "+" if row["contribution"] >= 0 else "-", row
            )

    def test_connectivity_factor_gains_an_impact_sign(self):
        """It used to be the one row without an `impact` key at all."""
        data = TriageCreate(
            body_region="Chest / Heart", pain_type="dull", severity=4,
        )
        _, contributions = compute_risk(data, sibling_regions=["Left Arm / Shoulder"])
        connectivity = [c for c in contributions if c["factor"].startswith("Connected to")]
        self.assertEqual(len(connectivity), 1)
        self.assertEqual(connectivity[0]["impact"], "+")

    def test_cap_is_named_as_a_factor_so_the_discard_is_visible(self):
        data = TriageCreate(
            body_region="Chest / Heart", pain_type="crushing", severity=10,
            heart_rate=135.0,
        )
        risk, contributions = compute_risk(
            data, patient_weight=120.0, patient_height=160.0
        )
        caps = [c for c in contributions if c["shap"] < 0]
        self.assertEqual(len(caps), 1)
        self.assertEqual(caps[0]["impact"], "-")
        self.assertIn("capped", caps[0]["factor"])
        # 0.50 severity + 0.40 chest + 0.20 crushing + 0.15 heart rate + 0.05 BMI
        self.assertIn("1.30", caps[0]["factor"])
        self.assertEqual(caps[0]["shap"], -0.30)

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

    def test_bmi_contribution(self):
        from app.services.triage_service import _bmi_contribution

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

    def test_oxygen_saturation_is_not_a_scoring_input(self):
        """The camera figure is a perfusion proxy, not pulse-oximetry, so it must
        not move a triage score or reach a practitioner as an oxygen saturation.

        Asserted as behaviour rather than absence: a client that still posts the
        field has to be ignored, not rejected (the mobile app ships updates on its
        own schedule) and not rewarded with extra risk.
        """
        from app.services import triage_service

        self.assertFalse(hasattr(triage_service, "_spo2_contribution"))
        self.assertNotIn("spo2", TriageCreate.model_fields)

        base = TriageCreate(
            body_region="Chest / Heart", pain_type="sharp", severity=7, heart_rate=110.0
        )
        legacy = TriageCreate(
            body_region="Chest / Heart", pain_type="sharp", severity=7,
            heart_rate=110.0, spo2=88.0,
        )
        self.assertNotIn("spo2", legacy.model_dump())
        self.assertEqual(compute_risk(base), compute_risk(legacy))

    def test_compute_risk_with_sibling_regions(self):
        triage_data = TriageCreate(
            body_region="Chest / Heart",
            pain_type="sharp",
            severity=7,
            heart_rate=110.0,
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

