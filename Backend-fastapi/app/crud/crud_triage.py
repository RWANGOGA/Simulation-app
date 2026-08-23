from typing import List, Optional
from sqlalchemy import select
from sqlalchemy.orm import Session
from app.models import TriageSession
from app.schemas import TriageCreate

def create_triage(db: Session, data: TriageCreate, risk_score: Optional[float] = None, shap_explanation: Optional[str] = None) -> TriageSession:
    session = TriageSession(**data.model_dump(), risk_score=risk_score, shap_explanation=shap_explanation)
    db.add(session)
    db.commit()
    db.refresh(session)
    return session

def list_triage(db: Session, limit: int = 50, patient_id: Optional[int] = None) -> List[TriageSession]:
    stmt = select(TriageSession).order_by(TriageSession.created_at.desc()).limit(limit)
    if patient_id is not None:
        stmt = stmt.where(TriageSession.patient_id == patient_id)
    return list(db.execute(stmt).scalars().all())

def get_triage(db: Session, session_id: int) -> Optional[TriageSession]:
    return db.get(TriageSession, session_id)

def get_latest_visit(db: Session, patient_id: int) -> List[TriageSession]:
    """
    Returns every TriageSession from the patient's most recent visit.

    "Most recent visit" = every row sharing the visit_id of the patient's
    newest submission. For older rows created before visit_id existed
    (visit_id is NULL), this naturally falls back to just that single row,
    since NULL never matches another NULL in the equality filter below —
    each null-visit_id row is effectively its own visit of one.
    """
    latest_stmt = (
        select(TriageSession)
        .where(TriageSession.patient_id == patient_id)
        .order_by(TriageSession.created_at.desc())
        .limit(1)
    )
    latest = db.execute(latest_stmt).scalar_one_or_none()
    if latest is None:
        return []

    if latest.visit_id is None:
        return [latest]

    stmt = (
        select(TriageSession)
        .where(
            TriageSession.patient_id == patient_id,
            TriageSession.visit_id == latest.visit_id,
        )
        .order_by(TriageSession.created_at.asc())
    )
    return list(db.execute(stmt).scalars().all())