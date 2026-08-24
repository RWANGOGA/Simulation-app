import unittest
from pydantic import ValidationError
from app.schemas import PatientCreate, TriageCreate

class TestSchemas(unittest.TestCase):
    def test_patient_create_valid(self):
        patient = PatientCreate(
            age=35,
            gender="Female",
            weight=62.5,
            height=168.0,
            preferred_language="en"
        )
        self.assertEqual(patient.age, 35)
        self.assertEqual(patient.gender, "Female")
        self.assertEqual(patient.weight, 62.5)

    def test_patient_create_invalid_age(self):
        with self.assertRaises(ValidationError):
            PatientCreate(age=150)

    def test_patient_create_invalid_weight(self):
        with self.assertRaises(ValidationError):
            PatientCreate(weight=-5.0)

    def test_triage_create_valid(self):
        triage = TriageCreate(
            body_region="Head",
            pain_type="throbbing",
            severity=7,
            direction="Towards Back",
            depth="Moderate"
        )
        self.assertEqual(triage.body_region, "Head")
        self.assertEqual(triage.severity, 7)

    def test_triage_create_invalid_severity(self):
        with self.assertRaises(ValidationError):
            TriageCreate(
                body_region="Chest",
                pain_type="sharp",
                severity=15
            )

if __name__ == "__main__":
    unittest.main()
