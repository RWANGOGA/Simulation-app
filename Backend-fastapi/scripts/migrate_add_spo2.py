"""
One-time migration: adds a nullable `spo2` column to triage_sessions.

Same situation as migrate_add_visit_id.py — this project has no Alembic and
app/main.py only runs Base.metadata.create_all(), which never alters
existing tables, so this has to be applied manually, once per database.

Usage:
    # Against your LOCAL database (uses DATABASE_URL from your local .env / config):
    python -m scripts.migrate_add_spo2

    # Against the PRODUCTION (Render) database: temporarily point
    # DATABASE_URL at the prod connection string (e.g. export it in your
    # shell, or run this from a Render shell session) and run the same
    # command again. Safe to run more than once — IF NOT EXISTS guards it.
"""
from sqlalchemy import text
from app.core.database import engine

def run():
    with engine.begin() as conn:
        conn.execute(text(
            "ALTER TABLE triage_sessions ADD COLUMN IF NOT EXISTS spo2 FLOAT"
        ))
    print("Done: triage_sessions.spo2 added (or already existed).")

if __name__ == "__main__":
    run()
