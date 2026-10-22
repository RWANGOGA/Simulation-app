"""Bootstrap and cleanup of practitioner accounts.

Two loose ends from the account-approval gate:

* ``scripts/seed_doctor`` created an unapproved practitioner, so a database
  bootstrapped from the command line had nobody who could sign in and nobody
  who could approve anyone.
* ``0006_add_doctor_roles`` approved every pre-existing row, which turned the
  leftover ``newdoc-*`` demo accounts into live approved accounts nobody owns.

The scripts are the fix, so the tests exercise the scripts — including the
dry run, because "don't write anything" is the part an operator has to be able
to trust on a database they care about.
"""
import pytest
from fastapi.testclient import TestClient

from app.api.v1.endpoints.auth import get_password_hash
from app.core.database import SessionLocal
from app.main import app
from app.models.doctor import ACCESS_ADMIN, ACCESS_PRACTITIONER, Doctor
from scripts import revoke_placeholder_doctors, seed_doctor

client = TestClient(app)


def _add_doctor(email, *, approved=True, active=True, level=ACCESS_PRACTITIONER,
                password="Placeholder123!"):
    db = SessionLocal()
    try:
        doctor = Doctor(
            email=email,
            hashed_password=get_password_hash(password),
            full_name=email,
            is_active=active,
            is_approved=approved,
            access_level=level,
        )
        db.add(doctor)
        db.commit()
        return doctor.id
    finally:
        db.close()


def _get(doctor_id):
    db = SessionLocal()
    try:
        return db.query(Doctor).filter(Doctor.id == doctor_id).first()
    finally:
        db.close()


def _by_email(email):
    db = SessionLocal()
    try:
        return db.query(Doctor).filter(Doctor.email == email).first()
    finally:
        db.close()


# --- seeding -------------------------------------------------------------


def test_seeded_account_is_approved_admin(monkeypatch):
    monkeypatch.setenv("SEED_DOCTOR_EMAIL", "bootstrap@hospital.org")
    monkeypatch.setenv("SEED_DOCTOR_PASSWORD", "Bootstrap123!")
    monkeypatch.delenv("SEED_DOCTOR_PROMOTE", raising=False)

    seed_doctor.run()

    db = SessionLocal()
    try:
        doctor = (
            db.query(Doctor).filter(Doctor.email == "bootstrap@hospital.org").first()
        )
    finally:
        db.close()
    assert doctor is not None
    # Unapproved would be unusable: /auth/login 403s and nobody could approve it.
    assert doctor.is_approved is True
    assert doctor.is_active is True
    assert doctor.access_level == ACCESS_ADMIN


def test_seeded_account_can_sign_in_and_approve(monkeypatch):
    """The point of the bootstrap is a usable deployment, not a row in a table."""
    monkeypatch.setenv("SEED_DOCTOR_EMAIL", "bootstrap@hospital.org")
    monkeypatch.setenv("SEED_DOCTOR_PASSWORD", "Bootstrap123!")
    monkeypatch.delenv("SEED_DOCTOR_PROMOTE", raising=False)
    seed_doctor.run()

    login = client.post(
        "/api/v1/auth/login",
        data={"username": "bootstrap@hospital.org", "password": "Bootstrap123!"},
    )
    assert login.status_code == 200, login.text
    headers = {"Authorization": f"Bearer {login.json()['access_token']}"}

    waiting = _add_doctor("waiting@hospital.org", approved=False)
    response = client.patch(
        f"/api/v1/auth/doctors/{waiting}", json={"is_approved": True}, headers=headers
    )
    assert response.status_code == 200, response.text


def test_seeding_twice_is_a_no_op(monkeypatch):
    monkeypatch.setenv("SEED_DOCTOR_EMAIL", "bootstrap@hospital.org")
    monkeypatch.setenv("SEED_DOCTOR_PASSWORD", "Bootstrap123!")
    seed_doctor.run()
    first = _by_email("bootstrap@hospital.org")

    monkeypatch.setenv("SEED_DOCTOR_PASSWORD", "SomethingElse123!")
    seed_doctor.run()
    second = _by_email("bootstrap@hospital.org")

    # Same row, same password: re-running must not quietly reset credentials.
    assert second.id == first.id
    assert second.hashed_password == first.hashed_password


def test_seed_does_not_silently_promote_an_existing_account(monkeypatch):
    doctor_id = _add_doctor("real@hospital.org", approved=False, level=ACCESS_PRACTITIONER)
    monkeypatch.setenv("SEED_DOCTOR_EMAIL", "real@hospital.org")
    monkeypatch.setenv("SEED_DOCTOR_PASSWORD", "Bootstrap123!")
    monkeypatch.delenv("SEED_DOCTOR_PROMOTE", raising=False)

    seed_doctor.run()

    doctor = _get(doctor_id)
    assert doctor.is_approved is False
    assert doctor.access_level == ACCESS_PRACTITIONER


def test_seed_promote_flag_repairs_an_existing_account(monkeypatch):
    doctor_id = _add_doctor(
        "real@hospital.org", approved=False, active=False, level=ACCESS_PRACTITIONER
    )
    monkeypatch.setenv("SEED_DOCTOR_EMAIL", "real@hospital.org")
    monkeypatch.setenv("SEED_DOCTOR_PASSWORD", "Bootstrap123!")
    monkeypatch.setenv("SEED_DOCTOR_PROMOTE", "1")

    seed_doctor.run()

    doctor = _get(doctor_id)
    assert doctor.is_approved is True
    assert doctor.is_active is True
    assert doctor.access_level == ACCESS_ADMIN


def test_seed_refuses_to_run_without_credentials(monkeypatch):
    monkeypatch.delenv("SEED_DOCTOR_EMAIL", raising=False)
    monkeypatch.delenv("SEED_DOCTOR_PASSWORD", raising=False)

    with pytest.raises(SystemExit):
        seed_doctor.run()


# --- placeholder cleanup -------------------------------------------------


def test_select_targets_only_matches_the_pattern():
    placeholder = _add_doctor("newdoc-1730000000@example.com")
    real = _add_doctor("nurse@hospital.org")

    db = SessionLocal()
    try:
        targets = revoke_placeholder_doctors.select_targets(db)
    finally:
        db.close()

    assert [doctor.id for doctor in targets] == [placeholder]
    assert real not in [doctor.id for doctor in targets]


def test_select_targets_skips_accounts_with_nothing_to_remove():
    _add_doctor("newdoc-gone@example.com", approved=False, active=False)

    db = SessionLocal()
    try:
        assert revoke_placeholder_doctors.select_targets(db) == []
    finally:
        db.close()


def test_select_targets_honours_keep():
    kept = _add_doctor("newdoc-keep@example.com")
    dropped = _add_doctor("newdoc-drop@example.com")

    db = SessionLocal()
    try:
        targets = revoke_placeholder_doctors.select_targets(
            db, keep=["NEWDOC-KEEP@example.com"]
        )
    finally:
        db.close()

    assert [doctor.id for doctor in targets] == [dropped]
    assert kept not in [doctor.id for doctor in targets]


def test_revoke_deactivates_without_deleting():
    placeholder = _add_doctor("newdoc-1@example.com")

    db = SessionLocal()
    try:
        targets = revoke_placeholder_doctors.select_targets(db)
        changed = revoke_placeholder_doctors.revoke(db, targets)
    finally:
        db.close()

    assert changed == 1
    doctor = _get(placeholder)
    # Kept, not deleted: triage history and the audit trail name this row.
    assert doctor is not None
    assert doctor.is_active is False
    assert doctor.is_approved is False


def test_revoked_account_can_no_longer_sign_in():
    _add_doctor("newdoc-2@example.com", password="Placeholder123!")

    db = SessionLocal()
    try:
        revoke_placeholder_doctors.revoke(
            db, revoke_placeholder_doctors.select_targets(db)
        )
    finally:
        db.close()

    login = client.post(
        "/api/v1/auth/login",
        data={"username": "newdoc-2@example.com", "password": "Placeholder123!"},
    )
    # Deactivated rows are answered exactly like unknown ones.
    assert login.status_code == 401


def test_revoke_refuses_to_remove_the_last_admin():
    from sqlalchemy import text

    db = SessionLocal()
    try:
        # Only the placeholder is an admin, so revoking it would leave the
        # deployment with nobody able to approve anyone.
        db.execute(text("UPDATE doctors SET access_level = 'practitioner'"))
        db.commit()
    finally:
        db.close()
    placeholder_admin = _add_doctor(
        "newdoc-admin@example.com", level=ACCESS_ADMIN
    )

    db = SessionLocal()
    try:
        targets = revoke_placeholder_doctors.select_targets(db)
        with pytest.raises(revoke_placeholder_doctors.NoAdminLeftError):
            revoke_placeholder_doctors.revoke(db, targets)
    finally:
        db.close()

    # Nothing was written on the way to the refusal.
    doctor = _get(placeholder_admin)
    assert doctor.is_approved is True
    assert doctor.is_active is True


def test_dry_run_writes_nothing():
    placeholder = _add_doctor("newdoc-3@example.com")

    exit_code = revoke_placeholder_doctors.run([])

    assert exit_code == 0
    doctor = _get(placeholder)
    assert doctor.is_active is True
    assert doctor.is_approved is True


def test_apply_revokes_and_reports_the_count(capsys):
    placeholder = _add_doctor("newdoc-4@example.com")

    exit_code = revoke_placeholder_doctors.run(["--apply"])

    assert exit_code == 0
    assert "Revoked 1 account(s)" in capsys.readouterr().out
    doctor = _get(placeholder)
    assert doctor.is_active is False
    assert doctor.is_approved is False


def test_run_reports_when_nothing_matches(capsys):
    exit_code = revoke_placeholder_doctors.run(["--email-pattern", "nobody-%"])

    assert exit_code == 0
    assert "No accounts match" in capsys.readouterr().out


def test_run_refuses_to_apply_when_it_would_orphan_the_deployment(capsys):
    from sqlalchemy import text

    db = SessionLocal()
    try:
        db.execute(text("UPDATE doctors SET access_level = 'practitioner'"))
        db.commit()
    finally:
        db.close()
    placeholder = _add_doctor("newdoc-5@example.com", level=ACCESS_ADMIN)

    exit_code = revoke_placeholder_doctors.run(["--apply"])

    assert exit_code == 2
    assert "no approved administrator would be left" in capsys.readouterr().out
    assert _get(placeholder).is_approved is True
