# 🏥 AtomyBridge Care

*"For the body does not consist of one member but of many." — 1 Corinthians 12:14*

**AtomyBridge Care** is an AI-powered, offline-first clinical triage platform that bridges the communication gap between patients in pain and medical practitioners. Patients visually map their pain on an interactive 3D body model, capture real-time vitals through the smartphone camera, and receive instant, **explainable** risk assessments — practitioners then review everything through a QR-based patient passport and a full clinical report.

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

1. The patient points at a **3D body model** where it hurts.
2. The app captures **objective vitals** (heart rate via camera PPG).
3. A **risk engine** scores the case and explains *why* (SHAP-style factor breakdown).
4. Everything is linked back to the patient through a **PII-free QR passport**.

## Architecture Overview

The system is a decoupled full-stack architecture built for performance, security, and scalability:

- **The Face & Hands — Flutter App** (Android / iOS / Web): an intuitive 3D interactive interface for patients. Edge-computing tasks such as PPG (photoplethysmography) heart-rate extraction run **on the device**.
- **The Brain & Memory — FastAPI Server** (Python): processes clinical data, calculates triage risk scores with explainable-AI logic, and persists records in PostgreSQL.

```text
┌──────────────────────────────┐        ┌──────────────────────────────┐        ┌─────────────┐
│   Flutter App (Patient)      │        │   FastAPI Server (Backend)   │        │ PostgreSQL  │
│                              │        │                              │        │  (Neon /    │
│  • 3D Body Map (GLB model)   │──JSON──▶  • Risk Engine + SHAP       │──SQL──▶│  Docker)    │
│  • PPG Camera Vitals         │  HTTP  │  • JWT Auth (bcrypt)         │        └─────────────┘
│  • QR Passport (no PII)      │        │  • Patient / Triage API      │
│  • Offline draft saving      │        │  • Self-healing schema       │
└──────────────────────────────┘        └──────────────────────────────┘
```

## How the System Works

### Patient journey (single visit)

```text
Welcome ──▶ Patient Info ──▶ 3D Body Map ──▶ Pain Wizard ──▶ Vitals (PPG) ──▶ Review ──▶ Report + QR
            (demographics)    (tap regions)   (severity,       (camera HR,     (confirm)   (risk score,
                                              duration, type)   BP estimate)                explanation)
```

1. **Intake** — the patient records demographics (age, sex, contact, next of kin, hospital). The draft is saved **offline locally** so an interrupted session can be resumed.
2. **Body mapping** — tapping the 3D model (via a JavaScript bridge into `model-viewer`) selects anatomical regions; a guided wizard captures pain intensity, duration, character, and aggravating factors per location.
3. **Vitals** — the camera flashes on the fingertip and extracts heart rate from blood-volume pulse (PPG); derived metrics follow fixed clinical calculation conventions.
4. **Risk scoring** — the submission is sent to `POST /api/v1/triage/`; the backend risk engine returns a score, a triage category, and a **SHAP-style factor list** (each factor with direction and % impact) so the result is explainable, not a black box.
5. **QR passport** — the result screen renders a QR code containing only the **visit reference** (pointer-only design: zero personal data in the code).

### Practitioner journey

1. The practitioner logs in (JWT) or registers via the practitioner signup flow.
2. On the dashboard they **scan the patient QR** (or enter the code manually).
3. The **clinical report** shows patient demographics, the triage decision card, the explainable SHAP factor bars, and the **visit timeline** across all sessions for that patient.
4. The practitioner can record a disposition (`PATCH .../decision`) which is persisted per visit.

### Backend request lifecycle

```text
Request ──▶ Pydantic schema validation ──▶ JWT auth (where required) ──▶ Service layer (risk engine)
        ──▶ SQLAlchemy CRUD ──▶ PostgreSQL ──▶ Response model
```

- **Self-healing schema**: on startup the app runs `create_all` plus schema-drift reconciliation statements, so fresh or partially-migrated databases heal themselves without manual migrations.
- **Risk engine**: deterministic, unit-tested scoring (`app/services/`) producing risk score, category, and per-factor explanations consumed by the report UI.

## Key Features

| Area | Feature |
|---|---|
| Patient | 3D interactive body map with tap detection |
| Patient | Camera-based PPG heart-rate capture |
| Patient | Offline-first drafts with resume |
| Patient | PII-free QR passport linking to the visit |
| Patient | Accessibility: text-size control (Small → Extra large) + dark / light / system theme |
| AI | Explainable risk scoring with SHAP-style factor bars |
| Practitioner | QR scan intake + manual code entry |
| Practitioner | Dashboard, clinical report, visit timeline, decision recording |
| Practitioner | Self-registration with professional fields |
| Data | Patient demographics captured at intake, stored, shown in report, carried via QR reference |

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | Flutter (Dart), `model_viewer_plus` (3D), `mobile_scanner` (QR), `camera` (PPG), `flutter_secure_storage` |
| Backend | FastAPI, SQLAlchemy, Pydantic v2 / pydantic-settings, `passlib` + `bcrypt`, PyJWT |
| Database | PostgreSQL 16 (Neon in production, Docker locally) |
| Auth | JWT bearer tokens (HS256), bcrypt-hashed passwords, secure on-device token storage |
| CI/CD | GitHub Actions (build APK + Web, deploy web to GitHub Pages), Render (backend) |
| Testing | `flutter_test` (widget + unit), `pytest` + `TestClient` |

## Project Structure

```text
.
├── Backend-fastapi/              # FastAPI backend ("The Brain")
│   ├── app/
│   │   ├── api/v1/endpoints/     # auth, patients, triage, health routers
│   │   ├── core/                 # config (.env), database, security (JWT/hash)
│   │   ├── crud/                 # SQLAlchemy data access
│   │   ├── models/               # ORM models (Doctor, Patient, TriageSession…)
│   │   ├── schemas/              # Pydantic request/response models
│   │   ├── services/             # risk engine / triage business logic
│   │   └── main.py               # app factory, self-healing schema startup
│   ├── scripts/seed_doctor.py    # env-driven practitioner seeding
│   ├── tests/                    # pytest suite (credentials centralized in conftest.py)
│   ├── docker-compose.yml        # local PostgreSQL
│   └── requirements.txt
│
├── simtack/                      # Flutter app ("The Face")
│   ├── lib/
│   │   ├── core/                 # api client, theme (AppTheme/AppPalette), accessibility
│   │   └── features/             # auth, body_map, vitals, review, report, dashboard,
│   │                             # patient_info, history, onboarding, settings, success
│   ├── assets/models/            # 3D GLB body model
│   ├── test/                     # widget + unit tests (credentials in test_doctor_credentials.dart)
│   └── pubspec.yaml
│
├── .github/workflows/build.yml   # CI: APK + Web build, GitHub Pages deploy
└── README.md
```

## Getting Started

### Prerequisites

- Python 3.11+
- Docker (local PostgreSQL) **or** a Neon PostgreSQL connection string
- Flutter SDK (the team pins **3.22.3**; see `flutter/` in the repo root)

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
| `SEED_DOCTOR_EMAIL` / `SEED_DOCTOR_PASSWORD` / `SEED_DOCTOR_NAME` | Required inputs for the seeding script |

> **Credential policy:** no email/password literals are hardcoded in app or seed code. Test credentials live in exactly one place per stack (`tests/conftest.py` for Python, `test/test_doctor_credentials.dart` for Flutter).

## API Reference

Base path: `/api/v1`

| Method | Route | Description | Auth |
|---|---|---|---|
| GET | `/health` | Liveness probe | — |
| POST | `/auth/register` | Create practitioner account | — |
| POST | `/auth/login` | Obtain JWT (OAuth2 form) | — |
| GET | `/auth/me` | Current practitioner profile | JWT |
| POST | `/patients/` | Register patient + demographics | — |
| GET | `/patients/{code}` | Fetch patient by code | — |
| POST | `/triage/` | Submit visit → risk score + explanation | — |
| GET | `/triage/` · `/triage/list` · `/triage/stats` | Sessions listing & dashboard stats | JWT |
| GET | `/triage/{session_id}` | Single session detail | JWT |
| GET | `/triage/patient/{code}` · `.../history` | All sessions / timeline for a patient | JWT |
| PATCH | `/triage/{session_id}/decision` | Record practitioner disposition | JWT |

## Testing

```bash
# Backend — from Backend-fastapi/
python -m pytest tests/ -q                 # 35 tests

# Frontend — from simtack/
flutter test                               # 64 tests (unit + widget)
flutter analyze                            # lint gate
```

CI runs the Flutter analyze/test matrix and APK/Web builds on every push (`.github/workflows/build.yml`).

## CI / CD & Deployment

- **Web app**: built by GitHub Actions and deployed to **GitHub Pages** (dynamic base URL handled at runtime).
- **Android APK**: built as a workflow artifact for distribution.
- **Backend**: deployed on **Render** against a **Neon PostgreSQL** instance. After merging to `main`, trigger a redeploy (or enable auto-deploy) so API changes go live.

## Security & Privacy

- Passwords hashed with **bcrypt**; JWTs signed HS256 with short-lived expiry.
- On-device tokens stored in **flutter_secure_storage** (Keychain / Keystore).
- **QR codes carry only visit references** — no personal data leaves the phone in the code.
- Credentials are never hardcoded; seeding and tests rely on environment/config.

## Contributing

1. Create a feature branch from `main`.
2. Keep both test suites green (`pytest` + `flutter test`) — post-merge verification is mandatory since the Flutter SDK pin (3.22.3) rejects newer APIs that may sneak in from teammate branches.
3. Open a PR with a clear description; squash-merge on approval.

---

Built with ❤️ for patients who can't always find the words.
