# AtomyBridge Care — API

FastAPI + PostgreSQL backend for the AtomyBridge Care patient and practitioner
apps. The Flutter clients live in `../simtack` and `../painpoint`.

## Running it locally

```bash
cp .env.example .env          # then fill in DATABASE_URL and SECRET_KEY
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt

docker compose up -d db       # postgres on 127.0.0.1:5432
alembic upgrade head          # see "Migrations" below
uvicorn app.main:app --reload --port 8000
```

Interactive docs are at `/docs` unless `ENVIRONMENT=production`, which disables
them along with the schema they would publish.

## Migrations

**Nothing runs the migrations for you.** Neither the Dockerfile, nor the
container entrypoint, nor application startup calls Alembic. `app/main.py`
creates two tables (`audit_logs`, `request_throttle`) with `checkfirst` because
leaving them out fails silently — a missing audit table just means "no trail".
Everything else has to be migrated explicitly.

```bash
alembic upgrade head                 # apply everything (every deploy)
alembic current                      # the revision this database is on
alembic history --verbose            # what exists, oldest first
alembic downgrade -1                 # undo the last migration only
alembic upgrade head --sql           # print the SQL without running it
```

`alembic.ini` leaves `sqlalchemy.url` empty on purpose: `alembic/env.py` reads
`DATABASE_URL` from the environment, so the CLI always migrates whatever
database the current shell points at. Check that before running `downgrade`.

Two things to know before a first deployment:

* `0006_add_doctor_roles` marks **every pre-existing account as approved** and
  promotes the earliest-created one to `admin`. Without that the deployment
  would have no administrator and new registrations could never be approved.
  Review who is in `doctors` before running it against a database you care
  about.
* Practitioner accounts created **after** that migration start unapproved and
  cannot sign in until an admin approves them through
  `PATCH /api/v1/auth/doctors/{id}`.

To create the first account from the command line instead:

```bash
SEED_DOCTOR_EMAIL=you@hospital.org \
SEED_DOCTOR_PASSWORD='a-real-password' \
python -m scripts.seed_doctor
```

### Is the running instance up to date?

`GET /api/v1/health/ready` reports `schema.current` (what the database says)
against `schema.expected` (the head revision, read from `alembic/versions`). A
mismatch is logged as `schema_behind_code` and does **not** fail the probe — a
schema behind the code is a deployment mistake, and taking a working instance
out of rotation over it would cause an outage rather than fix one.

## Health

| Endpoint | Question | Fails when |
| --- | --- | --- |
| `GET /api/v1/health` | Is the process alive? | Never — it has no dependencies. Restarting the container is the correct response. |
| `GET /api/v1/health/ready` | Should traffic come here? | Returns **503** when the database is unreachable. Restarting would not help; the instance should leave rotation. |

Use `/health/ready` for container and load-balancer probes; `docker-compose.yml`
already does.

## Anatomy assistant (`/api/v1/anatomy`)

These routes are reachable **without a token**, on purpose: the body map they
serve is part of anonymous patient intake, and a patient presenting at triage
has no account. The protection sits elsewhere:

* `POST /ask` is throttled per client IP (`ANATOMY_RATE_LIMIT`, 30 per 5
  minutes) because every uncached call is billed by the LLM provider.
* Conversations are scoped server-side. Clients send an opaque
  `conversation_id`; the store key is an HMAC of the caller's scope (their
  account when signed in, otherwise their address) and that id. `/clear`
  therefore cannot touch another caller's history, and neither can a request
  that reuses their id.
* The store is bounded — 512 conversations, one hour idle — and a read no
  longer creates an entry, so inventing ids cannot exhaust memory.
* Client-supplied `history` is capped at 12 turns of 500 characters and may
  only use the `user` and `assistant` roles.

A caller holding a valid practitioner token is scoped to that account instead
of their address, which keeps conversations apart behind a shared hospital NAT.

## Red-flag escalation (`/api/v1/triage`)

`risk_score` answers "how concerning is this overall". It is a weighted sum
clamped at 1.0, so it cannot express "this one finding is an emergency": mild
yet crushing chest pain scores 0.65 — the *medium* band — while clinically
needing an ambulance now. Every triage payload therefore also carries an
`escalation` object, computed by `triage_service.escalation_for`:

```json
{
  "level": "emergency",
  "action": "seek_emergency_care",
  "triggers": [
    {"code": "chest_pain_crushing", "detail": "Crushing chest pain"},
    {"code": "chest_pain_radiating", "detail": "Chest pain that spreads to another area"}
  ]
}
```

* `level` is `emergency`, `urgent` or `routine`; `action` says what the patient
  should do. `triggers` names every finding that fired, so a clinician can audit
  the verdict instead of trusting an opaque flag.
* **The rules never change the score.** They run beside `compute_risk`, and
  `tests/test_escalation.py` pins both directions: an emergency verdict on a
  medium score, and an unchanged score after escalation runs.
* The verdict is derived from the stored clinical columns **on every read**, so
  history is judged by the current rules, no migration is needed to add or
  correct one, and every route — create, history, QR lookup, practitioner
  view — reports the same thing.
* Escalated submissions are logged at `INFO` on creation
  (`triage <id> escalated emergency (risk=0.65, chest_pain_crushing)`) so a case
  is visible even when nobody has the dashboard open.

Current rules — chest pain that is crushing/stabbing, that radiates, or rated
8+/10; heart rate above 120 or below 50; pain rated 10/10 in a high-concern
region (chest, head, neck, abdomen). Heart rate 101-120, 10/10 pain elsewhere
and severe head pain are `urgent` rather than `emergency`. Findings are ranked
with emergencies first.

## Logs

Every module logs through the standard `logging` module; `configure_logging()`
in `app/core/logging.py` installs the single root handler at import.

```bash
LOG_LEVEL=INFO      # DEBUG | INFO | WARNING | ERROR
LOG_FORMAT=json     # one JSON object per line, for an aggregator
                    # "plain" (default) for a terminal
```

Deployments should set `LOG_FORMAT=json`. Every line carries `time`, `level`,
`logger`, `message` and `request_id`.

**Request correlation.** Every response returns `X-Request-ID`. A caller may
send one and it is echoed back, provided it matches `[A-Za-z0-9._:-]{1,64}`;
anything else is replaced with a freshly generated id. To trace a reported
failure, grep the logs for that id.

**Patient identifiers are not logged.** The access line records the path with
its parameters templated out — `/api/v1/triage/patient/{patient_code}`, not
`/api/v1/triage/patient/P-770043` — so the trail answers "how often" without
answering "who". `--no-access-log` in the Dockerfile exists for the same reason:
uvicorn's own access log would print the raw URL. Do not re-enable it.

## Tests

```bash
python -m pytest -q
```

`tests/conftest.py` derives a `<database>_test` name from `DATABASE_URL`
(override with `TEST_DATABASE_URL`), refuses to run against anything that does
not end in `_test`, creates the database if it is missing, and runs
`alembic upgrade head` against it. A local PostgreSQL is therefore required; no
`.env` is needed when `DATABASE_URL` and `SECRET_KEY` are set in the environment,
which is how CI runs it.

## Docker

```bash
docker compose up -d --build
docker compose logs -f api       # JSON lines
curl -s localhost:8003/api/v1/health/ready
```

The image runs as a non-root user, honours `$PORT`, and migrates nothing — run
`alembic upgrade head` as a release step (or from a one-off task) before the new
image starts serving.
