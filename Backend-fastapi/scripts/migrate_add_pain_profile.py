"""
One-time migration: adds Step 4/5 pain profile columns to triage_sessions.

Run after migrate_add_visit_id:
    python -m scripts.migrate_add_pain_profile

Safe to run multiple times — IF NOT EXISTS guards it.
"""
from sqlalchemy import text
from app.core.database import engine

def run():
    with engine.begin() as conn:
        # expansion_behavior
        conn.execute(text(
            "ALTER TABLE triage_sessions ADD COLUMN IF NOT EXISTS expansion_behavior VARCHAR"
        ))
        # triggers (JSON array stored as text)
        conn.execute(text(
            "ALTER TABLE triage_sessions ADD COLUMN IF NOT EXISTS triggers VARCHAR"
        ))
        # relievers (JSON array stored as text)
        conn.execute(text(
            "ALTER TABLE triage_sessions ADD COLUMN IF NOT EXISTS relievers VARCHAR"
        ))
        # daily_limitations (JSON array stored as text)
        conn.execute(text(
            "ALTER TABLE triage_sessions ADD COLUMN IF NOT EXISTS daily_limitations VARCHAR"
        ))
    print("Done: pain profile columns added (or already existed).")

if __name__ == "__main__":
    run()