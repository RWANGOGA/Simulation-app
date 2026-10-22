"""
One-time cleanup: revokes placeholder practitioner accounts.

`0006_add_doctor_roles` marked every pre-existing row as approved, so that
shipping the account-approval gate would not lock out the people already using
the system. That was right for real accounts and wrong for the ~125 `newdoc-*`
rows an earlier demo/load generator left behind: they became approved accounts
nobody owns, and each one is a way into every patient's clinical record if its
password is guessable.

This deactivates and un-approves them. It deliberately does not delete:
`triage_sessions.reviewed_by` and the audit trail name these accounts, and a
deleted doctor would leave history pointing at nothing.

Dry run by default — nothing is written until `--apply` is passed.

Usage:
    python -m scripts.revoke_placeholder_doctors            # show what would change
    python -m scripts.revoke_placeholder_doctors --apply    # do it

    # A different naming pattern (check it with a dry run first):
    python -m scripts.revoke_placeholder_doctors --email-pattern 'demo-%' --apply

    # Never touch one address even if it matches:
    python -m scripts.revoke_placeholder_doctors --keep you@hospital.org --apply
"""
import argparse
import sys
from typing import Iterable, List, Sequence

from app.core.database import SessionLocal
from app.models.doctor import Doctor

# What the abandoned demo generator used: `newdoc-<something>@...`.
DEFAULT_EMAIL_PATTERN = "newdoc-%"


class NoAdminLeftError(RuntimeError):
    """Raised instead of revoking the last administrator."""


def select_targets(
    db, pattern: str = DEFAULT_EMAIL_PATTERN, keep: Sequence[str] = ()
) -> List[Doctor]:
    """Accounts matching the pattern that still have any access to remove."""
    keep_set = {email.strip().lower() for email in keep if email}
    matches = db.query(Doctor).filter(Doctor.email.ilike(pattern)).all()
    return [
        doctor
        for doctor in matches
        if (doctor.is_active or doctor.is_approved)
        and doctor.email.lower() not in keep_set
    ]


def _admins_after(db, targets: Iterable[Doctor]) -> List[str]:
    targeted = {doctor.id for doctor in targets}
    return [
        doctor.email
        for doctor in db.query(Doctor).filter(Doctor.is_approved.is_(True)).all()
        if doctor.is_active
        and doctor.is_admin
        and doctor.id not in targeted
    ]


def revoke(db, targets: Sequence[Doctor]) -> int:
    """Deactivates and un-approves each target. Returns how many changed."""
    if targets and not _admins_after(db, targets):
        # A deployment with no administrator can never approve another
        # account, which is worse than leaving the placeholders around: it is
        # recoverable only by hand in SQL.
        raise NoAdminLeftError(
            "Refusing to revoke: no approved administrator would be left. "
            "Approve a real administrator first (PATCH /api/v1/auth/doctors/{id} "
            "or SEED_DOCTOR_PROMOTE=1 on the seed script)."
        )

    changed = 0
    for doctor in targets:
        doctor.is_active = False
        doctor.is_approved = False
        changed += 1
    if changed:
        db.commit()
    return changed


def run(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Deactivate placeholder practitioner accounts.",
    )
    parser.add_argument(
        "--email-pattern",
        default=DEFAULT_EMAIL_PATTERN,
        # argparse interpolates help strings, so the LIKE wildcard has to be
        # escaped or it raises "badly formed help string".
        help="SQL LIKE pattern for the addresses to revoke (default: "
        f"{DEFAULT_EMAIL_PATTERN.replace('%', '%%')}).",
    )
    parser.add_argument(
        "--keep",
        action="append",
        default=[],
        metavar="EMAIL",
        help="Address to leave alone even if it matches. Repeatable.",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Actually write the changes. Without this the script only reports.",
    )
    args = parser.parse_args(argv)

    db = SessionLocal()
    try:
        targets = select_targets(db, args.email_pattern, args.keep)
        if not targets:
            print(f"No accounts match {args.email_pattern!r} with access to remove.")
            return 0

        print(
            f"{len(targets)} account(s) match {args.email_pattern!r} "
            f"and still have access:"
        )
        for doctor in targets:
            print(
                f"  id={doctor.id:<6} {doctor.email:<40} "
                f"active={doctor.is_active} approved={doctor.is_approved} "
                f"level={doctor.access_level}"
            )

        if not args.apply:
            print("\nDry run: nothing was changed. Re-run with --apply to revoke.")
            return 0

        try:
            changed = revoke(db, targets)
        except NoAdminLeftError as error:
            print(f"\nERROR: {error}")
            return 2

        print(f"\nRevoked {changed} account(s): deactivated and un-approved.")
        return 0
    finally:
        db.close()


if __name__ == "__main__":
    sys.exit(run())
