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
