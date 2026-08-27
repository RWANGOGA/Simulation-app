from fastapi.testclient import TestClient
from app.main import app
from tests.conftest import DOCTOR_LOGIN

client = TestClient(app)


def _doctor_headers() -> dict:
    token = client.post("/api/v1/auth/login", data=DOCTOR_LOGIN).json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


def _submit(region: str, pain_type: str, severity: int, status: str | None = None):
    response = client.post(
        "/api/v1/triage/",
        json={"body_region": region, "pain_type": pain_type, "severity": severity},
    )
    assert response.status_code == 201
    session = response.json()
    if status is not None:
        patch = client.patch(
            f"/api/v1/triage/{session['id']}/decision",
            json={"status": status},
            headers=_doctor_headers(),
        )
        assert patch.status_code == 200
    return session


def test_reports_requires_jwt():
    response = client.get("/api/v1/triage/reports")
    assert response.status_code == 401


def test_reports_reflects_real_submitted_data():
    before = client.get("/api/v1/triage/reports", headers=_doctor_headers()).json()

    _submit("Chest / Heart", "Crushing", 8, status="closed")
    _submit("Chest / Heart", "Sharp", 5)
    _submit("Headache / Cranial", "Throbbing", 3)

    after = client.get("/api/v1/triage/reports", headers=_doctor_headers()).json()

    assert after["total"] == before["total"] + 3
    assert after["closed_count"] == before["closed_count"] + 1
    assert after["open_count"] == before["open_count"] + 2

    region_counts = {row["region"]: row["count"] for row in after["by_region"]}
    before_region_counts = {row["region"]: row["count"] for row in before["by_region"]}
    assert region_counts["Chest / Heart"] == before_region_counts.get("Chest / Heart", 0) + 2
    assert region_counts["Headache / Cranial"] == before_region_counts.get("Headache / Cranial", 0) + 1

    # by_region must be sorted by count, descending.
    counts = [row["count"] for row in after["by_region"]]
    assert counts == sorted(counts, reverse=True)

    assert after["avg_severity"] is not None
    assert after["avg_risk_score"] is not None


def test_reports_period_filter_excludes_nothing_freshly_submitted():
    # Everything submitted in a test run is "now", so week/month scoping
    # must still include it — this catches an inverted date comparison.
    before_week = client.get("/api/v1/triage/reports?period=week", headers=_doctor_headers()).json()
    before_month = client.get("/api/v1/triage/reports?period=month", headers=_doctor_headers()).json()

    _submit("Chest / Heart", "Sharp", 4)

    after_week = client.get("/api/v1/triage/reports?period=week", headers=_doctor_headers()).json()
    after_month = client.get("/api/v1/triage/reports?period=month", headers=_doctor_headers()).json()
    after_all = client.get("/api/v1/triage/reports?period=all", headers=_doctor_headers()).json()

    assert after_week["total"] == before_week["total"] + 1
    assert after_month["total"] == before_month["total"] + 1
    assert after_all["total"] >= after_week["total"]


def test_reports_rejects_invalid_period():
    response = client.get("/api/v1/triage/reports?period=year", headers=_doctor_headers())
    assert response.status_code == 422
