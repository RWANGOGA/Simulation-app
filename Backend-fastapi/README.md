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
