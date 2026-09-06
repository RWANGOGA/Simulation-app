# 🏥 AtomyBridge Care

*"For the body does not consist of one member but of many." — 1 Corinthians 12:14*

**AtomyBridge Care** is an AI-powered, offline-first clinical triage platform that bridges the communication gap between patients in pain and medical practitioners. Patients visually map their pain on an interactive 2D body atlas, capture real-time vitals through the smartphone camera, receive instant explainable risk assessments, and interact with AI-generated anatomy insights — practitioners then review everything through a QR-based patient passport and a full clinical report.

---

## Table of Contents

- [Core Idea](#core-idea)
- [Architecture Overview](#architecture-overview)
- [How the System Works](#how-the-system-works)
- [Key Features](#key-features)
- [Tech Stack](#tech-stack)
- [Project Structure](#project-structure)
- [Getting Started](#getting-started)
- [Environment Variables](#environment-variables)
- [API Reference](#api-reference)
- [Testing](#testing)
- [CI / CD & Deployment](#ci--cd--deployment)
- [Security & Privacy](#security--privacy)
- [Contributing](#contributing)

---

## Core Idea

In low-resource clinical settings, patients often cannot describe their symptoms precisely, and practitioners have no structured record of the visit. AtomyBridge Care replaces verbal descriptions with a **standardized digital intake**:

1. The patient points at a **2D body atlas** where it hurts.
2. The app captures **objective vitals** (heart rate via camera PPG).
3. A **risk engine** scores the case and explains *why* (SHAP-style factor breakdown).
4. An **AI anatomy assistant** retrieves relevant medical knowledge and generates personalized insights, suggested questions, and red flags.
5. Everything is linked back to the patient through a **PII-free QR passport**.

## Architecture Overview

The system is a decoupled full-stack architecture built for performance, security, and scalability:

- **The Face & Hands — Flutter App** (Android / iOS / Web): an intuitive 2D interactive interface for patients. Edge-computing tasks such as PPG (photoplethysmography) heart-rate extraction run **on the device**.
- **The Brain & Memory — FastAPI Server** (Python): processes clinical data, calculates triage risk scores with explainable-AI logic, powers a hybrid RAG anatomy assistant, and persists records in PostgreSQL.

```text
┌──────────────────────────────┐        ┌──────────────────────────────┐        ┌─────────────┐
│   Flutter App (Patient)      │        │   FastAPI Server (Backend)   │        │ PostgreSQL  │
│                              │        │                              │        │  (Neon /    │
│  • 2D Body Atlas (tap view)  │──JSON──▶  • Risk Engine + SHAP       │──SQL──▶│  Docker)    │
│  • PPG Camera Vitals         │  HTTP  │  • JWT Auth (bcrypt)         │        └─────────────┘
│  • QR Passport (no PII)      │        │  • Hybrid RAG Retriever      │
│  • Offline draft saving      │        │  • LLM-powered anatomy AI    │
│  • Conversation memory       │        │  • Self-healing schema       │
└──────────────────────────────┘        └──────────────────────────────┘
```

## How the System Works

### Patient journey (single visit)

```text
Welcome ──▶ Patient Info ──▶ 2D Body Map ──▶ Pain Wizard ──▶ Vitals (PPG) ──▶ Review ──▶ Report + QR
             (demographics)    (tap regions)   (severity,       (camera HR,     (confirm)   (risk score,
                                               duration, type)   BP estimate)                explanation,
                                                                                                  AI insights)
```

1. **Intake** — the patient records demographics (age, sex, contact, next of kin, hospital). The draft is saved **offline locally** so an interrupted session can be resumed.
2. **Body mapping** — tapping the 2D anatomy atlas selects anatomical regions; a guided wizard captures pain intensity, duration, character, aggravating factors, triggers, relievers, and daily limitations per location.
3. **AI Anatomy Insights** — after tapping a region, the app fetches RAG-powered insights from the backend: relevant medical structures, likely conditions, red flags, suggested questions, and citations. Patients can answer suggested questions directly in the app.
4. **Vitals** — the camera flashes on the fingertip and extracts heart rate from blood-volume pulse (PPG); derived metrics follow fixed clinical calculation conventions.
5. **Risk scoring** — the submission is sent to `POST /api/v1/triage/`; the backend risk engine returns a score, a triage category, and a **SHAP-style factor list** (each factor with direction and % impact) so the result is explainable, not a black box.
6. **QR passport** — the result screen renders a QR code containing only the **visit reference** (pointer-only design: zero personal data in the code).

### Practitioner journey

1. The practitioner logs in (JWT) or registers via the practitioner signup flow.
2. On the dashboard they **scan the patient QR** (or enter the code manually).
3. The **clinical report** shows patient demographics, the triage decision card, the explainable SHAP factor bars, the **visit timeline**, and **answered AI questions** across all sessions for that patient.
4. The practitioner can record a disposition (`PATCH .../decision`) which is persisted per visit.

### Backend request lifecycle

```text
Request ──▶ Pydantic schema validation ──▶ JWT auth (where required) ──▶ Service layer (risk engine / RAG retriever)
         ──▶ SQLAlchemy CRUD ──▶ PostgreSQL ──▶ Response model
```

- **Self-healing schema**: on startup the app runs `create_all` plus schema-drift reconciliation statements, so fresh or partially-migrated databases heal themselves without manual migrations.
- **Risk engine**: deterministic, unit-tested scoring (`app/services/`) producing risk score, category, and per-factor explanations consumed by the report UI.
- **Hybrid RAG retriever**: combines BM25 lexical search with TF-IDF vector similarity using Reciprocal Rank Fusion (RRF), with optional LLM reranking and conversation memory.

## Key Features

| Area | Feature |
|---|---|
| Patient | 2D interactive body atlas with precise region detection |
| Patient | Camera-based PPG heart-rate capture |
| Patient | Offline-first drafts with resume |
| Patient | PII-free QR passport linking to the visit |
| Patient | Accessibility: text-size control (Small → Extra large) + dark / light / system theme |
| Patient | Multi-language support: English, Luganda, Swahili, Runyankore |
| AI | Explainable risk scoring with SHAP-style factor bars |
| AI | Hybrid RAG anatomy assistant with BM25 + TF-IDF search |
| AI | LLM-powered insights with citations and conversation memory |
| AI | Interactive suggested questions with answer persistence |
| Practitioner | QR scan intake + manual code entry |
| Practitioner | Dashboard, clinical report, visit timeline, decision recording |
| Practitioner | Self-registration with professional fields |
| Data | Patient demographics, pain profiles, triggers, relievers, daily limitations |
| Data | Question answers stored per region and displayed in clinical reports |

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | Flutter (Dart), 2D anatomy tap view, `mobile_scanner` (QR), `camera` (PPG), `flutter_secure_storage` |
| Backend | FastAPI, SQLAlchemy, Pydantic v2 / pydantic-settings, `passlib` + `bcrypt`, PyJWT |
| Database | PostgreSQL 16 (Neon in production, Docker locally) |
| AI/LLM | Groq API for anatomy insights, hybrid BM25+TF-IDF retriever, LLM reranking |
| Auth | JWT bearer tokens (HS256), bcrypt-hashed passwords, refresh tokens, secure on-device token storage |
| CI/CD | GitHub Actions (build APK + Web, deploy web to GitHub Pages), Render (backend) |
| Testing | `flutter_test` (widget + unit), `pytest` + `TestClient` |

## Project Structure

```text
.
├── Backend-fastapi/              # FastAPI backend ("The Brain")
│   ├── app/
│   │   ├── api/v1/endpoints/     # auth, patients, triage, anatomy routers
│   │   ├── core/                 # config (.env), database, security (JWT/hash)
│   │   ├── crud/                 # SQLAlchemy data access
│   │   ├── models/               # ORM models (Doctor, Patient, TriageSession, RefreshToken)
│   │   ├── schemas/              # Pydantic request/response models
│   │   ├── services/             # risk engine, RAG retriever, LLM client
│   │   └── main.py               # app factory, self-healing schema startup
│   ├── scripts/                  # seed_doctor, migrations
│   ├── tests/                    # pytest suite
│   ├── docker-compose.yml        # local PostgreSQL
│   └── requirements.txt
│
├── simtack/                      # Flutter app ("The Face")
│   ├── lib/
│   │   ├── core/                 # api client, theme (AppTheme/AppPalette), accessibility
│   │   └── features/             # auth, body_map, vitals, review, report, dashboard,
│   │                             # patient_info, history, onboarding, settings, success
│   ├── assets/
│   │   ├── models/               # 3D GLB body model
│   │   └── anatomy/              # 2D anatomy atlas images and region mappings
│   ├── test/                     # widget + unit tests
│   └── pubspec.yaml
│
└── .github/workflows/build.yml   # CI: APK + Web build, GitHub Pages deploy
```

## Getting Started

### Prerequisites

- Python 3.11+
- Docker (local PostgreSQL) **or** a Neon PostgreSQL connection string
- Flutter SDK — the team works against a **3.22.3** stable checkout (this repo vendors one at `flutter/`; run commands via `../flutter/bin/flutter`, or verify with `flutter --version`). CI uses the stable channel (`.github/workflows/build.yml`); note the app must stay compatible with 3.22 APIs

### Backend

```bash
cd Backend-fastapi

# 1. Start PostgreSQL
docker compose up -d

# 2. Virtual environment + dependencies
python3 -m venv venv
source venv/bin/activate          # Windows: venv\Scripts\activate
pip install -r requirements.txt

# 3. Configure environment (see table below)
cp .env.example .env              # then fill in DATABASE_URL and SECRET_KEY

# 4. Run — tables are created and reconciled automatically on startup
uvicorn app.main:app --reload --port 8000

# 5. (Optional) seed a practitioner — credentials come from the environment,
#    never from hardcoded defaults:
SEED_DOCTOR_EMAIL=you@hospital.org SEED_DOCTOR_PASSWORD='StrongPass1' \
    python -m scripts.seed_doctor
```

Interactive API docs: <http://localhost:8000/docs>

### Frontend

```bash
cd simtack
flutter pub get
flutter run -d chrome              # or an emulator/device
```

The app resolves its API base URL at runtime (localhost in development, the Render URL in release builds).

## Environment Variables

Backend (`Backend-fastapi/.env`, loaded by pydantic-settings):

| Variable | Purpose |
|---|---|
| `DATABASE_URL` | SQLAlchemy connection string (PostgreSQL) |
| `SECRET_KEY` | JWT signing key — **must** be overridden in production |
| `GROQ_API_KEY` | Optional Groq API key for LLM-powered anatomy insights |
| `INVITE_CODE` | Optional invite code to gate practitioner registration |
| `SEED_DOCTOR_EMAIL` / `SEED_DOCTOR_PASSWORD` | **Required** inputs for the seeding script |
| `SEED_DOCTOR_NAME` | Optional display name (defaults to `Seeded Practitioner`) |

> **Credential policy:** seed credentials come exclusively from environment variables (`SEED_DOCTOR_EMAIL` / `SEED_DOCTOR_PASSWORD` — both required). Test suites use shared test constants defined in one place per stack (`tests/conftest.py` for Python, `test/test_doctor_credentials.dart` for Flutter); the Python constants honor the same `SEED_DOCTOR_*` env vars so seeding and tests can never drift apart.

## API Reference

Base path: `/api/v1`

| Method | Route | Description | Auth |
|---|---|---|---|
| GET | `/health` | Liveness probe | — |
| POST | `/auth/register` | Create practitioner account | — |
| POST | `/auth/login` | Obtain JWT + refresh token (OAuth2 form) | — |
| POST | `/auth/refresh` | Refresh access token | Refresh token |
| POST | `/auth/logout` | Revoke refresh token | Refresh token |
| GET | `/auth/me` | Current practitioner profile | JWT |
| PATCH | `/auth/me` | Update practitioner profile | JWT |
| POST | `/patients/` | Register patient + demographics | — |
| GET | `/patients/{code}` | Fetch patient by code | — |
| PATCH | `/patients/{code}` | Update patient demographics | JWT |
| POST | `/triage/` | Submit visit → risk score + explanation | — |
| GET | `/triage/` · `/triage/list` · `/triage/stats` | Sessions listing & dashboard stats | JWT |
| GET | `/triage/history` | Paginated session history with filters | JWT |
| GET | `/triage/reports` | Practitioner reports breakdown | JWT |
| GET | `/triage/{session_id}` | Single session detail | JWT |
| GET | `/triage/patient/{code}` · `.../history` | All sessions / timeline for a patient | JWT |
| PATCH | `/triage/{session_id}/decision` | Record practitioner disposition | JWT |
| GET | `/anatomy/regions` | List available anatomy regions | — |
| POST | `/anatomy/ask` | Get AI-powered anatomy insights (RAG + LLM) | — |
| POST | `/anatomy/clear` | Clear conversation history | — |

## Testing

```bash
# Backend — from Backend-fastapi/
python -m pytest tests/ -q                 # 52 tests (requires PostgreSQL)

# Frontend — from simtack/
flutter test                               # 97 tests (unit + widget)
flutter analyze                            # lint gate
```

CI runs the Flutter analyze/test matrix and APK/Web builds on every push (`.github/workflows/build.yml`).

## CI / CD & Deployment

- **Web app**: built by GitHub Actions and deployed to **GitHub Pages** (dynamic base URL handled at runtime).
- **Android APK**: built as a workflow artifact for distribution.
- **Backend**: deployed on **Render** against a **Neon PostgreSQL** instance. After merging to `main`, trigger a redeploy (or enable auto-deploy) so API changes go live.

## Security & Privacy

- Passwords hashed with **bcrypt**; JWTs signed HS256 with short-lived expiry (15 min) + refresh tokens.
- On-device tokens stored in **flutter_secure_storage** (Keychain / Keystore).
- **QR codes carry only visit references** — no personal data leaves the phone in the code.
- SQL injection prevented via parameterized queries throughout.
- CORS restricted to known origins; request size limited to 10MB.
- IP-based rate limiting on public endpoints to prevent abuse.
- Trusted host middleware in production.
- Credentials are never hardcoded in app or seed code; seeding uses required environment variables.

## Contributing

1. Create a feature branch from `main`.
2. Keep both test suites green (`pytest` + `flutter test`) — post-merge verification is mandatory since the Flutter SDK pin (3.22.3) rejects newer APIs that may sneak in from teammate branches.
3. Open a PR with a clear description; squash-merge on approval.

---

Built with ❤️ for patients who can't always find the words.
