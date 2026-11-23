# 🏥 AtomyBridge Care

*"For the body does not consist of one member but of many." — 1 Corinthians 12:14*

**AtomyBridge Care** is an offline-first clinical triage platform. A patient maps
pain on a body atlas, answers a structured pain wizard, and gets a device-computed
risk score, red-flag escalation and SATS-shaped triage category — with no server,
no account and no network required. A practitioner later opens the visit through a
QR passport or patient code and records a disposition.

The server is a **mirror and multi-device memory**, not a dependency. If the
backend is unreachable the clinical product still works end to end; an outbox
uploads the visit when connectivity returns.

This README is the working reference for the whole repository: architecture, data
flow, clinical rules, offline model, security posture, API surface, operations and
test strategy. Where the system makes a claim, the claim is tied to the code or
bytes that make it true.

---

## Table of Contents

- [Design principles](#design-principles)
- [Repository layout](#repository-layout)
- [Architecture](#architecture)
- [End-to-end flows](#end-to-end-flows)
- [Clinical engine](#clinical-engine)
- [Anatomy assistant](#anatomy-assistant)
- [Offline-first layer](#offline-first-layer)
- [QR passport](#qr-passport)
- [Backend internals](#backend-internals)
- [API reference](#api-reference)
- [Data model](#data-model)
- [Configuration](#configuration)
- [Running locally](#running-locally)
- [Testing](#testing)
- [CI / CD](#ci--cd)
- [Security and privacy](#security-and-privacy)
- [Known limitations](#known-limitations)
- [Contributing](#contributing)

---

## Design principles

1. **The device is the source of truth for a visit.** Capture, scoring, escalation,
   tier, the anatomy knowledge base and the report all run locally. A clinic with
   no connection loses nothing.
2. **The server is a mirror, never a gate.** Screens do not call HTTP. They call
   `OfflineRepository`; `SyncService` is the only clinical writer to the network.
3. **Derive clinical verdicts on read.** `risk_score` is stored, but escalation
   and tier are recomputed from the current rules every time a record is read, so
   correcting a rule re-judges history instead of freezing an old mistake.
4. **Claims must match bytes.** A QR code is only called "offline" or "encrypted"
   when the payload actually is; a score is called "explainable" because the factor
   rows sum to it, not because a library named SHAP was imported.
5. **Abstain rather than invent.** The anatomy retriever refuses to serve context
   that the complaint does not support, and the LLM falls back to retrieved text
   instead of rendering an error.

---

## Repository layout

```text
.
├── Backend-fastapi/              # FastAPI + PostgreSQL backend ("the brain")
│   ├── app/
│   │   ├── api/v1/endpoints/     # health, auth, patients, triage, anatomy, audit
│   │   ├── core/                 # settings, database, logging, request context
│   │   ├── crud/                 # SQLAlchemy data access
│   │   ├── models/               # Doctor, Patient, TriageSession, RefreshToken,
│   │   │                         # AuditLog, RequestThrottle
│   │   ├── schemas/              # Pydantic v2 contracts
│   │   ├── services/             # triage engine, RAG retriever, LLM, organ lookup,
│   │   │                         # audit, throttle, evaluation
│   │   ├── data/                 # anatomy_kb.json, body_graph.py, organ data
│   │   └── main.py               # app factory, middleware, startup reconciliation
│   ├── alembic/versions/         # schema migrations 0001 → 0007
│   ├── scripts/                  # export assets, simulation, seeds, legacy migrations
│   ├── tests/                    # pytest suite (real PostgreSQL)
│   ├── docker-compose.yml        # local PostgreSQL 15
│   └── Dockerfile                # python:3.11-slim + entrypoint
│
├── simtack/                      # Flutter app ("the face")
│   ├── lib/
│   │   ├── core/
│   │   │   ├── clinical/         # RiskEngine, AnatomyEngine, ClinicalData
│   │   │   ├── offline/          # LocalDatabase, OfflineRepository, SyncService,
│   │   │   │                     # passport cipher/record/QR
│   │   │   ├── network/          # ApiClient, AuthService
│   │   │   ├── locale/           # language registry + controller
│   │   │   ├── theme/            # design tokens, accessibility
│   │   │   └── vitals/           # camera PPG pipeline
│   │   └── features/             # onboarding, patient_info, body_map, review,
│   │                             # report, success, dashboard, history, auth,
│   │                             # profile, settings
│   ├── assets/
│   │   ├── clinical/             # generated risk rules, body graph, KB, organ data
│   │   ├── anatomy/              # 2D atlas images + region id maps
│   │   └── anatomy3d/            # 3D viewer + tracked full/lite atlases
│   ├── test/                     # unit, widget, parity, security, l10n tests
│   ├── docs/                     # design standard + threat model
│   └── pubspec.yaml
│
├── flutter/                      # vendored Flutter SDK 3.22.3 (gitignored)
├── .github/workflows/build.yml   # CI: backend tests → Flutter analyze/test → builds
└── README.md                     # this file
```

---

## Architecture

```text
┌──────────────────────────────── Flutter app (simtack) ────────────────────────────────┐
│                                                                                       │
│  UI screens                                                                           │
│    │                                                                                  │
│    ▼                                                                                  │
│  OfflineRepository ──────────────▶ LocalDatabase                                      │
│    │                               • one atomic JSON document                         │
│    │                               • AES-256-GCM envelope when a keystore exists      │
│    │                               • local ids count down from -1                     │
│    │                                                                                  │
│    ├── RiskEngine / AnatomyEngine ◀── assets/clinical/*.json (generated by Python)    │
│    └── SyncService ── HTTP ──▶ FastAPI ──▶ SQLAlchemy ──▶ PostgreSQL                  │
│                                  ▲                                                    │
│  AuthService ────────────────────┘  /auth (JWT + rotating refresh tokens)             │
│                                                                                       │
└───────────────────────────────────────────────────────────────────────────────────────┘
```

### Component responsibilities

| Component | Responsibility |
|---|---|
| `OfflineRepository` | The only clinical data API the UI sees. Reproduces server semantics (visit grouping, band filters, aggregate shapes, 404s) on the device. |
| `LocalDatabase` | Atomic local store, encrypted at rest where possible, with negative local ids for unsynced rows. |
| `SyncService` | Ordered outbox drain (patient → triage → decision), bounded retries, no destructive cleanup. |
| `RiskEngine` | Dart port of the Python scoring, escalation and tier rules; parity-tested against recorded backend output. |
| `AnatomyEngine` | Dart port of retrieval for the bundled anatomy knowledge base, used when offline. |
| `AuthService` | Online JWT sessions plus an offline PBKDF2 credential cache with a 7-day trust window. |
| `ApiClient` | All HTTP, model parsing, token storage, refresh de-duplication, cold-start timeouts. |
| FastAPI services | Same clinical logic for the server path, plus persistence, audit, throttling and LLM depth. |

---

## End-to-end flows

### Patient visit

```text
Welcome → Patient Info → Body Map → Pain Wizard → Review → Result + QR
           (optional)     (tap regions)  (per region)   (confirm)  (score, tier,
                                                                   factors, passport)
```

1. **Onboarding** — language consent (English, Luganda, Runyankole, Lusoga,
   Kiswahili, sign language) and accessibility preferences.
2. **Patient info** — demographics are optional so an anonymous walk-in stays
   fast. A patient code is minted client-side when possible, making sync
   idempotent.
3. **Body map** — the 2D atlas resolves a tap to one of the app's region strings.
   The 3D viewer is optional and falls back to the 2D atlas if WebGL/context is
   unavailable.
4. **Pain wizard** — per region: severity, character, duration, direction, depth,
   expansion, triggers, relievers, functional impact, and answers to suggested
   questions.
5. **Review** — every point is scored on the device. `OfflineRepository.sendTriage`
   creates the visit, groups points by `visit_id`, applies sibling-region context
   and returns the same response shape as the server.
6. **Result** — score, band, escalation, SATS tier, factor breakdown, timeline and
   a QR passport. The visit is already durable locally before any network call.

### Practitioner visit

1. Sign in online (JWT) or offline against a cached credential within the trust
   window.
2. Scan a QR passport. The scanner decides the payload family from its bytes:
   - `ABP1:…` → sealed record, decrypted with the printed six-character phrase;
   - otherwise → a patient code / report URL to open.
3. The clinical report shows demographics, the triage decision, explainable factor
   bars, the visit timeline, and answered AI questions.
4. `PATCH /triage/{id}/decision` records the disposition; offline it is queued in
   the outbox and replayed later.

### Sync and reconciliation

- The outbox is ordered: **patient → triage points → decision**.
- Records are never deleted locally after sync; the server is a copy, not the
  owner of the device's history.
- Transport failures (timeout, no route) do not consume retry attempts; server
  rejections do, up to a bounded limit.
- Client-minted patient codes and visit ids make retries idempotent.
- Local negative ids are replaced by server ids when a record is accepted.

---

## Clinical engine

The engine lives in `Backend-fastapi/app/services/triage_service.py` and is ported
to `simtack/lib/core/clinical/risk_engine.dart`. `risk_rules.json` is generated
from the Python constants, so the two implementations cannot drift silently.

### Risk score

`compute_risk()` produces a clamped weighted sum in `[0, 1]` and a factor list.
It is **not** SHAP; it is an additive, auditable contribution table.

| Factor | Contribution |
|---|---|
| Severity | `round(severity / 10 × 0.50, 2)` |
| Region | chest/heart `0.40`, head/cranial `0.35`, neck `0.30`, abdomen/stomach `0.25`, back `0.20`, arm/shoulder/elbow/wrist/hand `0.15` (left side `0.20`), leg/knee/hip/foot `0.10`, default `0.10` |
| Pain character | crushing `0.20`, stabbing `0.15`, sharp `0.12`, burning `0.10`, cramping `0.09`, throbbing `0.08`, numb `0.08`, dull `0.05`, default `0.05` |
| Heart rate | `>120` or `<50` bpm `+0.15`; `>100` bpm `+0.10`; `0`/null means “no measurement” |
| Co-reported adjacency | one-hop graph bump: high `0.25`, moderate `0.12`, low `0.05` |
| Propagation | `edge_weight × neighbour_severity / 10 × 0.10`, rounded half-up; edge weights high `1.00`, moderate `0.50`, low `0.25` |
| BMI | `≥30` or `<18.5` adds `0.05` |
| Cap | if the raw sum exceeds `1.00`, a negative “capped at 1.00” row records the discarded amount so the explanation still sums to the score |

Bands: `< 0.40` low, `0.40–0.699` medium, `≥ 0.70` high.

The body graph is a **hand-authored one-hop adjacency table** of textbook
referred-pain relationships. There is no GNN, no learned message passing and no
training. Propagation is ordinary rule-based code walking that table; it is
described as such everywhere.

### Escalation

`escalation_for()` runs beside the score, because a weighted sum cannot express
“this single finding is an emergency”. It returns `level`, `action` and typed
`triggers`.

| Level | Rules |
|---|---|
| **emergency** | crushing/stabbing chest pain; chest pain with a radiating direction; chest severity `≥ 8`; heart rate `>120` or `<50`; severity `10` in chest/heart/head/cranial/neck/abdomen/stomach |
| **urgent** | heart rate `>100`; severity `10` elsewhere; head severity `≥ 8` |
| **routine** | none of the above |

Actions: emergency → `seek_emergency_care`; urgent → `seek_urgent_care`;
routine → `routine_review`.

### SATS-shaped triage tier

`triage_tier()` maps the same findings onto four categories. Rules come first,
score second:

| Tier | Category | Decision |
|---|---|---|
| **red** | emergency | any emergency flag, or a critical heart rate |
| **orange** | very urgent | any urgent flag, or score `≥ 0.70` in a high-concern region |
| **yellow** | urgent | score `≥ 0.40` |
| **green** | routine | otherwise |

This borrows SATS category names and colours; it is **SATS-shaped, not the SATS
algorithm, and not clinically validated**. The repository reports specification
conformance against designed vignettes, never inter-rater reliability, because
there is one non-clinician author and no second labeler.

### Parity

`Backend-fastapi/scripts/export_offline_assets.py` generates:

- `simtack/assets/clinical/risk_rules.json` — weights, escalation constants, tiers;
- `body_graph.json` — region connections and concern levels;
- `anatomy_kb.json` — byte-identical copy of the backend KB;
- `organ_reports.json` / `part_to_organ.json` — tap-to-organ lookup data;
- `simtack/test/fixtures/clinical_golden.json` — recorded Python outputs.

`simtack/test/clinical_parity_test.dart` replays the fixtures against the Dart
engine. A transcription slip in either implementation fails the suite.

---

## Anatomy assistant

Two paths answer a tapped region:

1. **Organ lookup** (`/anatomy/part/{name}`, `/anatomy/organs`) — the tap already
   says which part was touched, so this is a dictionary lookup, not a search. It
   covers the 34 body-map regions plus mesh names and returns description,
   functions, sub-parts, disorders, red flags, suggested questions and common
   conditions.
2. **Retrieval + LLM** (`POST /anatomy/ask`) — for free-text questions.

### Retrieval stages

`app/services/anatomy_retriever.py` separates three questions:

1. **Eligibility** — the tapped region and body side are facts. A chunk describing
   the opposite limb is never context.
2. **Grounding** — a monograph is served only if the complaint names its subject,
   shares two distinctive words with it, or the patient tapped its region. Ranking
   cannot answer whether anything fits at all, so the retriever abstains instead of
   inventing context.
3. **Ranking** — BM25 lexical score and TF-IDF cosine similarity, fused with
   Reciprocal Rank Fusion, with synonym expansion and laterality handling.

### LLM layer

`app/services/llm_client.py` calls a Groq OpenAI-compatible endpoint with a strict
JSON prompt. `GROQ_MODEL` is configurable (default `openai/gpt-oss-20b`). If the
key is missing, the request fails or the JSON cannot be parsed, the caller falls
back to the retrieved chunks, so the UI never renders an “AI unavailable” error
state for a question that has evidence behind it.

### Offline

`simtack/lib/core/clinical/anatomy_engine.dart` is the Dart port used with the
bundled KB. It keeps the same eligibility, grounding and ranking separation, so an
offline answer is drawn from the same evidence as an online one.

---

## Offline-first layer

### `LocalDatabase`

- One JSON document written atomically (temp file + rename semantics at the
  abstraction level), so an interrupted write cannot truncate the store.
- Local ids count **down from -1**; server ids are positive. The sign tells the
  sync layer which rows still need uploading.
- When a platform keystore is available the document is sealed with AES-256-GCM
  under an `ABL1:` envelope. On web and in tests, where no keystore exists, the
  store is plaintext and the app says so rather than implying encryption.
- Stores patients, sessions/visits, drafts, outbox entries, cached credentials and
  settings.

### `OfflineRepository`

Reproduces the server contract on-device:

- patient create/lookup by code, including client-minted codes;
- triage create grouped by `visit_id`, sibling-region context, derived escalation
  and tier;
- latest visit, patient history, paginated lists, dashboard statistics and report
  aggregates;
- consistent not-found and validation behaviour.

### `SyncService`

- Drains the outbox in dependency order and stops on the first retryable failure.
- Distinguishes transport failure (do not burn an attempt) from server rejection
  (burn an attempt, bounded).
- Never deletes a local record after upload; the device keeps its history.
- Replaces negative ids with server ids when a response is accepted.

### Offline authentication

- Online: bcrypt on the server, HS256 JWT (15 min), refresh token (7 days) with
  single-use rotation and a 60-second grace window. Reuse after the window revokes
  every live token for that doctor.
- Offline: the app caches a PBKDF2-HMAC-SHA256 verifier, not the password, and
  allows sign-in for **7 days** after the last successful online confirmation.
- Approval and deactivation are enforced from the cache: a deactivated account
  cannot keep using an old offline credential indefinitely.
- A server rejection during `restoreSession()` ends the local session, so the app
  does not open onto a dashboard whose every request fails.
- Device-only accounts (registered with no server) are approved locally and are
  never uploaded.

---

## QR passport

There are two payload families, and the scanner decides which one it has by
reading the bytes — never by a caption.

### 1. Sealed passport

```text
ABP1:base64url(salt | IV | ciphertext | tag)
```

- AES-256-GCM over a compact clinical record.
- Opened with the six-character phrase printed on the card.
- Only used when the sealed payload fits the byte budget (≤ 700 bytes); otherwise
  the app falls back to a pointer.
- Carries the essentials a receiving station needs: patient code, visit id, tier,
  pain points (region, severity, character, tier). It does **not** carry name,
  phone, address, next of kin, the full factor breakdown or questionnaire answers.

### 2. Pointer passport

```text
https://…/#/report/<patient-code>
```

- A plain reference to the online report, with no clinical content in the code.
- Requires connectivity and an authorised session to open the full record.

Both families are rendered by the same screen; the UI may only claim “offline” or
“encrypted” after checking `qr_passport.dart` / `passport_record.dart`, which is
what keeps the caption honest.

---

## Backend internals

### Startup and middleware (`app/main.py`)

- `FastAPIOffline` app; lifespan verifies the database and performs **limited**
  self-healing:
  - creates `audit_logs` and `request_throttle` if missing;
  - adopts nullable columns the ORM declares but the live table lacks.
- Alembic remains the source of truth for every other schema change. The container
  entrypoint runs `alembic upgrade head` before starting uvicorn.
- Middleware order: `RequestContextMiddleware` (outermost, assigns `X-Request-ID`)
  → CORS → TrustedHost (production) → app.
- A custom 500 handler re-attaches CORS headers so browser clients see the real
  error instead of an opaque CORS failure.
- Security headers, a 10 MB request cap, and `/docs`/OpenAPI disabled in
  production.

### Routers

| Module | Prefix | Purpose |
|---|---|---|
| `health` | `/health` | liveness and readiness |
| `auth` | `/auth` | register, login, refresh, logout, profile, doctor administration |
| `patients` | `/patients` | intake, public lookup, authenticated update |
| `triage` | `/triage` | scoring, lists, stats, reports, history, decisions |
| `anatomy` | `/anatomy` | regions, organs, part lookup, status, ask, clear |
| `audit` | `/audit` | admin-only access trail |
| `admin` | `/admin` | administrator console: overview, accounts, activity, sessions |

### Authentication and accounts

- Passwords hashed with bcrypt.
- JWT HS256, 15-minute access tokens.
- Refresh tokens are single-use and rotated; a 60-second grace window tolerates
  concurrent tabs; replay after the window revokes the whole family.
- Login lockout after 5 failed attempts for 300 seconds (configurable constants).
- Registration can be gated by `INVITE_CODE`.
- The first account bootstraps as an approved **admin**. Later accounts start
  **unapproved** and cannot sign in until an admin approves them.
- Exactly two access levels: `practitioner` and `admin`. `role` is a display-only
  job title. An admin cannot demote or deactivate themselves.
- Passwords are **at least 8 characters** and must include upper case, lower
  case, a number and a special character. The Flutter registration form uses
  the same 8-character minimum; existing passwords are never rewritten.

### Cross-cutting services

| Service | Behaviour |
|---|---|
| `throttle.py` | Database-backed rate limits shared across workers and restarts. |
| `audit.py` | Writes through an isolated session so the trail survives a rolled-back request; failures are logged and swallowed, never turned into a 500. |
| `evaluation.py` | Pure weighted/unweighted kappa functions over `(tool_tier, reference_tier)` pairs; refuses to report inter-rater reliability without a clinician label and a second labeler. |
| `organ_lookup.py` | Dictionary lookup for tapped parts, with an explicit “coming soon” fallback. |

### Health checks

- `GET /api/v1/health` — liveness only; never touches the database.
- `GET /api/v1/health/ready` — checks the database and compares the live Alembic
  revision with the migration head; returns `503` when traffic should be pulled.

### Schema migrations

`alembic/versions/` is a linear chain:

```text
0001 initial schema
0002 reconcile existing schema
0003 pain profile fields
0004 audit log
0005 request throttle
b84cd4531bab approval + access level
0006 doctor roles
0007 clinician tier
```

Run `alembic upgrade head` after pulling. Do not rely on `create_all` for new
columns or tables.

---

## API reference

Base path: `/api/v1`

| Method | Route | Description | Auth |
|---|---|---|---|
| GET | `/health` | Liveness probe | — |
| GET | `/health/ready` | Database + migration readiness | — |
| POST | `/auth/register` | Create a practitioner account (may require invite) | — |
| POST | `/auth/login` | OAuth2 password form → access + refresh token | — |
| POST | `/auth/refresh` | Rotate refresh token, issue new access token | Refresh token |
| POST | `/auth/logout` | Revoke the presented refresh token | Refresh token |
| GET | `/auth/me` | Current practitioner profile | JWT |
| PATCH | `/auth/me` | Update own profile | JWT |
| GET | `/auth/doctors` | List accounts | Admin |
| PATCH | `/auth/doctors/{id}` | Approve, deactivate, change access level | Admin |
| POST | `/patients/` | Register patient (client-minted code allowed) | — |
| GET | `/patients/{code}` | Public lookup, identity fields redacted | — |
| PATCH | `/patients/{code}` | Update demographics | JWT |
| POST | `/triage/` | Submit one pain point → score, escalation, tier | — |
| GET | `/triage/` | Recent sessions | JWT |
| GET | `/triage/list` | Paginated sessions with filters | JWT |
| GET | `/triage/history` | Paginated history with date/band filters | JWT |
| GET | `/triage/stats` | Dashboard aggregates | JWT |
| GET | `/triage/reports` | Report breakdown | JWT |
| GET | `/triage/patient/{code}` | All sessions for a patient | JWT |
| GET | `/triage/patient/{code}/history` | Patient timeline | JWT |
| GET | `/triage/{session_id}` | Single session | JWT |
| PATCH | `/triage/{session_id}/decision` | Record practitioner disposition | JWT |
| GET | `/anatomy/regions` | Region list for the body map | — |
| GET | `/anatomy/organs` | Organ list | — |
| GET | `/anatomy/part/{name}` | Tap-to-organ lookup | — |
| GET | `/anatomy/status` | LLM availability / configuration status | — |
| POST | `/anatomy/ask` | Grounded retrieval + optional LLM answer | — |
| POST | `/anatomy/clear` | Clear a conversation | — |
| GET | `/admin/overview` | Account, patient, triage and audit aggregates | Admin |
| GET | `/admin/users` | Paginated accounts with counts, search and status filters | Admin |
| PATCH | `/admin/users/{id}` | Approve, deactivate or promote an account (delegates to the auth handler) | Admin |
| GET | `/admin/users/{id}` | Full practitioner profile with their own audit history | Admin |
| GET | `/admin/patients` | Paginated patient register with live session counts and last risk | Admin |
| GET | `/admin/patients/{id}` | Patient demographics, triage sessions and access history | Admin |
| GET | `/admin/activity` | Paginated audit trail with action/outcome/actor filters | Admin |
| GET | `/admin/sessions` | Paginated operational session view with risk/status filters | Admin |
| GET | `/audit/logs` | Paginated access trail | Admin |
| GET | `/audit/patients/{code}` | Access trail for one patient | Admin |

Public routes redact identity fields (`PublicPatientResponse`,
`_PUBLIC_REDACTED_FIELDS`). Rate limits apply to public intake and anatomy.

---

## Data model

| Table | Key fields | Notes |
|---|---|---|
| `doctors` | email, hashed_password, full_name, role, access_level, is_approved, is_active | First account becomes approved admin |
| `patients` | anonymous_code, demographics, contact, next of kin, hospital, language, notes | Most fields optional |
| `triage_sessions` | patient_id, visit_id, body_region, pain fields, vitals, risk_score, shap_explanation, question_answers, clinician_tier, decision | `shap_explanation` is the JSON factor list; `spo2` is retired |
| `refresh_tokens` | doctor_id, token hash, expiry, revoked, rotated_from | Single-use rotation and reuse detection |
| `audit_logs` | actor kind/id, action, resource, outcome, request id, timestamp | No patient identifiers in the row |
| `request_throttle` | bucket, window, count | Shared across workers |

`risk_score` is persisted; `escalation` and `tier` are derived on every read and
are not columns.

---

## Configuration

Backend reads `Backend-fastapi/.env` through pydantic-settings.

| Variable | Required | Purpose |
|---|---|---|
| `DATABASE_URL` | yes | SQLAlchemy PostgreSQL URL |
| `SECRET_KEY` | yes (≥32 chars) | JWT signing key; the default is insecure and logged as such |
| `ENVIRONMENT` | no | `development` / `production`; production disables docs and enforces TrustedHost |
| `INVITE_CODE` | no | Gates practitioner self-registration |
| `GROQ_API_KEY` | no | Enables LLM depth; without it the retriever still answers |
| `GROQ_MODEL` | no | Default `openai/gpt-oss-20b` |
| `GROQ_BASE_URL` | no | OpenAI-compatible endpoint |
| `GROQ_TIMEOUT_SECONDS` | no | Default 20 |
| `ALLOWED_ORIGINS` | no | Comma-separated CORS allowlist |
| `TRUSTED_HOSTS` | no | Comma-separated Host allowlist |
| `LOG_LEVEL` / `LOG_FORMAT` | no | `plain` or `json` |
| `TEST_DATABASE_URL` | no | Test database override |
| `SEED_DOCTOR_EMAIL` / `SEED_DOCTOR_PASSWORD` | seed only | Required inputs for `scripts.seed_doctor`; never hardcoded |

Flutter build-time settings:

| Setting | Purpose |
|---|---|
| `--dart-define=API_BASE_URL=…` | Override the API base URL |
| `--dart-define=API_DEBUG_HOST=…` | Debug host, default `127.0.0.1` |

Release builds default to `https://backend-fastapi-linv.onrender.com/api/v1`.

> Never commit `.env`, tokens, patient data or a real `GROQ_API_KEY`.

---

## Running locally

### Prerequisites

- Python 3.11+
- Docker (for local PostgreSQL 15) **or** a PostgreSQL connection string
- Flutter **3.22.3** — this repo vendors the SDK at `flutter/`; run
  `../flutter/bin/flutter` or ensure your `flutter --version` matches

### Backend

```bash
cd Backend-fastapi

docker compose up -d db

python3 -m venv venv
source venv/bin/activate            # Windows: venv\Scripts\activate
pip install -r requirements.txt

cp .env.example .env                # set DATABASE_URL and SECRET_KEY

alembic upgrade head
uvicorn app.main:app --reload --port 8000
```

- API: <http://localhost:8000/api/v1>
- Docs (development only): <http://localhost:8000/docs>
- Seed a practitioner from environment variables:

```bash
SEED_DOCTOR_EMAIL=you@hospital.org SEED_DOCTOR_PASSWORD='StrongPass1' \
  python -m scripts.seed_doctor
```

The first registered account becomes an approved admin; use it to approve later
accounts through `PATCH /auth/doctors/{id}`.

### Flutter app

```bash
cd simtack
../flutter/bin/flutter pub get
../flutter/bin/flutter run -d chrome        # or an emulator / device
```

The app works with the backend stopped. Start the backend only when you want to
exercise sync, practitioner sign-in against the server, or LLM answers.

#### 3D body viewer and offline web

The interactive 3D body is served from `simtack/web/anatomy3d/`. On a browser it
is the default renderer and resolves taps to the same 34 region strings the
clinical engine uses. To keep the first body on screen fast, the viewer first
loads a **skin-only atlas** (~1 MB) generated by
`simtack/scripts/build_anatomy_lite.py`, then upgrades quietly to the full
BodyParts3D atlas in the background. The layer bar switches between **Skin,
Muscles, Veins, Arteries and All** — the muscle and vessel meshes were always
in the atlas but were previously hidden behind a debug-only toggle.

`model-viewer` is self-hosted in `web/vendor/`, so no CDN request is needed.
Flutter's generated service worker precaches the web build, including the 3D
viewer and its atlases, so a page that has loaded once opens offline. The
availability gate is still WebGL: browsers without a context use the bundled
2D atlas, and non-web builds always use it.

#### Administrator console

Administrators get an extra **Administration → Admin Console** entry in the
practitioner sidebar. It is a five-tab operational view, all fed by live
backend queries:

| Tab | Contents |
|---|---|
| Overview | Account/patient/triage/audit counters; tier, risk and escalation distributions; 14-day daily volume; activity grouped by action/outcome/actor; top regions; recent activity; snapshot provenance |
| Users | Search and filter accounts; approve, deactivate, reactivate, promote and demote; open a full practitioner profile with their own audit history |
| Patients | Searchable patient register with session counts and last risk; open a full record with demographics, triage sessions and who accessed it |
| Activity | The complete audit trail with action, outcome, actor and resource filters |
| Sessions | Recent triage points with risk and status filters (anonymous patient code only) |

The console is **server-authoritative but cache-backed**. `AdminRepository`
writes every successful read into the same encrypted local document as the
clinical records, under a separate `cache` map. With no connection it serves the
last snapshot and shows an explicit *“Showing the snapshot saved … Connect to
refresh”* banner, so stale figures are never mistaken for live ones. Account
changes are never cached: a mutation needs the server, and a failed mutation says
so rather than pretending an account was approved. The sidebar link is hidden
from non-admins for convenience; every route re-checks the role on the server.

### Regenerating offline clinical assets

Run this whenever the Python rules, body graph or KB change:

```bash
cd Backend-fastapi
python -m scripts.export_offline_assets
cd ../simtack
../flutter/bin/flutter test test/clinical_parity_test.dart
```

---

## Testing

### Backend

```bash
cd Backend-fastapi
python -m pytest tests/ -q
```

- 30 test files, ~312 test functions.
- Requires a real PostgreSQL; `conftest.py` creates `<db>_test` from
  `DATABASE_URL`/`TEST_DATABASE_URL` and runs `alembic upgrade head`.
- Covers auth rotation/reuse, approval, throttling, audit, triage scoring,
  escalation, tiers, retrieval grounding, evaluation arithmetic and health.

### Flutter

```bash
cd simtack
../flutter/bin/flutter analyze
../flutter/bin/flutter test
```

- 53 test files, ~397 test declarations.
- Includes clinical parity, tier rules, offline trust window, encryption envelope,
  passport sealing/opening, localisation, design-token enforcement and widget
  flows.
- `flutter analyze` is a gate, not advisory: the project targets Flutter 3.22.3
  APIs (for example `withOpacity`, not newer replacements).

### What the tests deliberately do not claim

- The vignette simulation measures **specification conformance** against designed
  targets, not clinical validity.
- Inter-rater kappa is reported as **unavailable**, because there is one author and
  no second labeler.
- Parity tests prove the Dart port matches recorded Python output, not that either
  engine is clinically correct.

---

## CI / CD

`.github/workflows/build.yml` runs, in order:

1. Backend tests against PostgreSQL.
2. `flutter analyze` and `flutter test`.
3. Android APK build.
4. Web build.
5. GitHub Pages deploy (main only).

Build and deploy jobs `needs` the test jobs, so a failing suite blocks deployment.
Flutter is pinned to **3.22.3**; `simtack/l10n.yaml` uses
`synthetic-package: false` so generated localisations are committed under
`lib/l10n/` rather than frozen in `.dart_tool/`.

Production:

- **Web app** → GitHub Pages (`/Simulation-app/` base href).
- **Android** → workflow artifact.
- **Backend** → Render against Neon PostgreSQL; the container entrypoint runs
  Alembic before serving.

---

## Security and privacy

- **Passwords**: bcrypt; never stored or logged in plaintext.
- **Sessions**: short-lived JWT plus rotating single-use refresh tokens with reuse
  detection.
- **Device tokens**: `flutter_secure_storage` (Keychain / Keystore).
- **Offline credentials**: PBKDF2 verifier, 7-day trust window, approval and
  deactivation enforced from the cache.
- **QR**: either a pointer with no clinical content or an AES-256-GCM sealed record
  opened by a printed phrase; never name, phone, address or next of kin.
- **Public endpoints**: identity fields redacted; database-backed rate limits.
- **Transport / host**: CORS allowlist, TrustedHost in production, security
  headers, 10 MB request cap, access logs disabled to avoid PHI in URLs.
- **Audit**: every patient-record access is recorded with actor, action, resource,
  outcome and request id — not patient identifiers.
- **SQL**: parameterised through SQLAlchemy.
- **Logs**: request ids and structured logging; secrets and PHI are not logged.

`simtack/docs/threat-model.md` states the residual risks: a compromised unlocked
device, a shared practitioner device, the offline trust window, and the fact that
an encrypted passport is only as strong as the six-character phrase.

---

## Known limitations

These are deliberate boundaries, not hidden behaviour:

1. **SATS-shaped, not validated.** The tier borrows SATS categories; no clinician
   labelled the vignette set.
2. **“SHAP-style” means additive contributions.** The factor rows sum to the score
   and are auditable; no Shapley values are computed.
3. **The app is device-first.** Clinical reads come from the local store or a QR
   passport, not from a server pull. Two practitioners on different devices do not
   automatically see the same history; the server is a mirror.
4. **The administrator console is server-authoritative.** Accounts, the audit
   trail and system-wide statistics do not exist on one device. Reads fall back
   to a labelled cached snapshot when offline, but approvals, deactivations and
   role changes require a connection; there is no locally-authoritative queue
   for them.
5. **LLM depth needs a key and a connection.** Without either, the assistant falls
   back to retrieved knowledge-base text; it does not invent an answer.
6. **The backend needs PostgreSQL.** The app does not; the server does.
7. **Release URLs are hardcoded** (Render API, GitHub Pages report link). Change
   them in `api_client.dart` / the report screen when the deployment moves.
8. **`spo2` is retired.** The column remains on older rows; nothing reads or
   writes it, because a camera perfusion proxy is not pulse oximetry.
9. **The interactive 3D body viewer is web-only.** It renders in an iframe from
   `simtack/web/anatomy3d/` (the tracked `assets/anatomy3d/` tree is its source
   copy). On mobile the app uses the bundled 2D atlas instead. On web the lite
   skin atlas (~1 MB) is shown first and the full ~30 MB atlas upgrades in the
   background; both are cached by Flutter's generated service worker, so the
   3D body also works offline after the first visit.

---

## Contributing

1. Branch from `main`.
2. Keep both suites green: `pytest` and `flutter analyze && flutter test`.
3. If you touch clinical constants, the body graph or the anatomy KB, regenerate
   `simtack/assets/clinical/*` and commit the parity fixtures with the change.
4. If you touch the schema, add an Alembic migration; do not extend the startup
   self-healing beyond the two runtime tables and nullable-column adoption.
5. Update this README when behaviour changes. A claim that no longer matches the
   bytes is a bug.

---

Built with ❤️ for patients who can't always find the words.
