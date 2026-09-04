"""
One-time migration: adds a nullable `question_answers` JSON column to triage_sessions.

This project has no Alembic — app/main.py only runs
Base.metadata.create_all(), which never alters existing tables — so this
has to be applied manually, once per database.

Usage:
    # Against your LOCAL database (uses DATABASE_URL from your local .env / config):
    python -m scripts.migrate_add_question_answers

    # Against the PRODUCTION (Render) database: temporarily point
    # DATABASE_URL at the prod connection string and run the same
    # command again. Safe to run more than once — IF NOT EXISTS guards it.
"""
from sqlalchemy import text
from app.core.database import engine

def run():
    with engine.begin() as conn:
        conn.execute(text(
            "ALTER TABLE triage_sessions ADD COLUMN IF NOT EXISTS question_answers JSONB"
        ))
    print("Done: triage_sessions.question_answers added (or already existed).")

if __name__ == "__main__":
    run()
