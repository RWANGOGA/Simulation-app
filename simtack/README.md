# 🏥 AtomyBridge Care — Flutter App

*"For the body does not consist of one member but of many." — 1 Corinthians 12:14*

**AtomyBridge Care** is an AI-powered, offline-first clinical triage Flutter application. It empowers patients to visually map their pain on a 2D body atlas, capture real-time vitals via smartphone cameras, receive instant explainable risk assessments, and interact with AI-generated anatomy insights.

---

## Architecture Overview

The Flutter app is the patient-facing interface ("The Face") of the AtomyBridge Care platform. It communicates with the FastAPI backend via JSON/HTTP.

```text
[ Flutter App (Patient) ]  --(HTTP/JSON)-->  [ FastAPI Server (Doctor) ]  --(SQL)-->  [ PostgreSQL DB ]
        |                                              |
        +-- 2D Body Atlas (tap detection)             +-- Risk Engine
        +-- PPG Camera Vitals                          +-- Hybrid RAG Retriever
        +-- QR Passport (no PII)                       +-- LLM-powered anatomy AI
        +-- Offline draft saving
        +-- Conversation memory
```

## Key Features

| Area | Feature |
|---|---|
| Patient | 2D interactive body atlas with precise region detection |
| Patient | Camera-based PPG heart-rate capture |
| Patient | Offline-first drafts with resume |
| Patient | PII-free QR passport linking to the visit |
| Patient | Accessibility: text-size control + dark / light / system theme |
| Patient | Multi-language support: English, Luganda, Swahili, Runyankore |
| AI | Hybrid RAG anatomy assistant with BM25 + TF-IDF search |
| AI | LLM-powered insights with citations and conversation memory |
| AI | Interactive suggested questions with answer persistence |
| Data | Expanded pain profiles: triggers, relievers, daily limitations, symptom description, tags |

## Project Structure

```text
simtack/
├── lib/
│   ├── core/
│   │   ├── network/             # API client, models, auth
│   │   ├── storage/             # Offline draft storage
│   │   ├── theme/               # AppTheme, AppPalette, accessibility
│   │   └── widgets/             # Reusable widgets (anatomy insight cards)
│   └── features/
│       ├── auth/                # Login, registration
│       ├── body_map/            # 2D body atlas, pain points, pain details
│       ├── patient_info/        # Demographics intake
│       ├── vitals/              # PPG camera heart-rate capture
│       ├── review/              # Review & submit screen
│       ├── report/              # Clinical report, QR passport
│       ├── dashboard/           # Practitioner dashboard
│       ├── history/             # Visit timeline
│       ├── onboarding/          # Welcome, language selection
│       ├── settings/            # Accessibility, language picker
│       └── success/             # Post-submission confirmation
├── assets/
│   ├── models/                  # 3D GLB body model
│   └── anatomy/                 # 2D anatomy atlas images and region mappings
├── test/                        # Widget + unit tests
└── pubspec.yaml                 # Flutter dependencies
```

## Getting Started

### Prerequisites

- Flutter SDK 3.22.3+ (stable channel)

### Installation

```bash
cd simtack

# 1. Install dependencies
flutter pub get

# 2. Run the app on Chrome (or your preferred device)
flutter run -d chrome
```

### Running Tests

```bash
# Run all tests
flutter test

# Run linter
flutter analyze
```

## Configuration

The app resolves its API base URL at runtime:
- **Development**: `http://localhost:8000/api/v1`
- **Release**: Configured via build-time environment or the Render backend URL

## API Integration

The backend is an **optional sync target**, not a dependency: no screen calls it.
Every read and write the app performs is answered locally (see below), and
`SyncService` is the only thing that talks to the API, when one is reachable:

- **Auth**: `/auth/login`, `/auth/register`, `/auth/me`, `/auth/refresh`, `/auth/logout`
- **Patients**: `/patients/` (create), `/patients/{code}` (read), `/patients/{code}` (update)
- **Triage**: `/triage/` (submit), `/triage/list`, `/triage/stats`, `/triage/history`, `/triage/patient/{code}`, `/triage/{session_id}`, `/triage/{session_id}/decision`
- **Anatomy AI**: `/anatomy/regions`, `/anatomy/ask`, `/anatomy/clear`

See the [root README](../README.md) for full API documentation.

## Running with no backend at all

The app is local-first. Started with no server — no network, no laptop, nothing —
both halves work end to end:

| Patient | Practitioner |
| --- | --- |
| Capture a profile or stay anonymous, get a scannable code | Register an account on the device and sign in |
| Record every pain point, scored on the device | Search patients, read the visit timeline |
| Read the report, risk band, red flags and escalation banner | Read the SHAP breakdown, file a decision |
| Ask the anatomy assistant | Edit their own profile |

To try it, run the app with the backend stopped:

```bash
cd simtack
flutter run            # nothing else needed
```

**Where the data lives.** `LocalDatabase` keeps every patient, every triage
session and the sync outbox in one JSON document in `shared_preferences`, and
writes it atomically: a crash mid-write leaves the previous document intact
rather than half a visit. Device-created rows are numbered *downwards* from -1,
so a negative id can never be mistaken for a server id and "has this reached the
server?" has an honest answer.

**The numbers are the backend's numbers.** Scoring, escalation and anatomy
retrieval are ports of the Python service, not approximations. `test/fixtures/`
holds 433 risk vectors and 30 anatomy vectors recorded from the backend, and
`test/clinical_parity_test.dart` replays them; `tool/` regenerates the bundled
`assets/clinical/*.json` from the Python source. If the two disagree, the build
fails — a report scored offline is the same report.

**Nothing is lost waiting for a connection.** Every write also lands in the
outbox, drained in creation order (patient → report → decision). Transport
failures stop the pass without spending an attempt; a server rejection is
recorded and skipped; after `SyncService.maxAttempts` a record is left alone but
**never deleted**. Patient codes are minted on the device and accepted by the
server through `anonymous_code`, so a retried create is idempotent — a duplicate
gets a 409 that leaks no patient fields and is treated as "already there".

**Drafts are intents, not a queue.** "Save for later" keeps a draft the patient
can resume. Drafts are no longer uploaded and deleted at launch; a leftover one
is committed to the device under the same local id, so resuming works and a
successful submit leaves nothing behind to resubmit as a duplicate.

**Known limits.** One device is the unit of truth: there is no multi-device
merge, and a record edited on two devices resolves last-write-wins on the server.
The bundled clinical assets are loaded before the first frame; if they cannot be
read the app refuses to score rather than guessing.

## Offline sign-in and account revocation

Practitioners can sign in with no connectivity, so the app keeps a local copy
of their account. That copy is a **trust window, not a permanent credential**:

- A successful sign-in, registration, or `/auth/me` stamps `lastVerifiedAt` —
  the last moment the *server* confirmed the account.
- Offline sign-in works for `AuthService.offlineTrustWindow` (7 days) from that
  stamp. After that the app asks the practitioner to sign in once while
  connected instead of letting a stale cache represent a live account.
- A cached account that is still pending approval, or was deactivated, is
  refused offline with a 403 — the server's last known decision stands even
  with no network.
- At launch `main()` calls `AuthService.restoreSession()`, which re-checks
  `/auth/me`. A 401/403 means the account really is gone: the token is cleared
  and every cached row's trust anchor is revoked. The wait is bounded to five
  seconds so a sleeping backend cannot hold up the first frame; a network
  failure is not treated as a revocation.

Passwords are stored as PBKDF2-HMAC-SHA256 (20 000 iterations, one random
16-byte salt per account) and compared in constant time. A cache written by an
older build still verifies through the legacy path and is silently rehashed on
the next successful offline sign-in.

### Accounts that only ever exist on the device

When registration is submitted and no server can be reached, the account is
created *on the device* instead of being refused — a clinic with no backend has
no administrator to ask, and refusing would make the app unusable there. Such an
account is approved on the device (`isApproved: true`, `isSynced: false`), which
means `DoctorDraft.isDeviceAccount` is true for it and:

- the approval gate and the 7-day trust window **do not apply** — both exist to
  bound what a *copy of a server account* may do, and there is no copy here;
- it can never be uploaded later, because only a password hash is kept, so it can
  never be confused with an account the server knows about.

Everything else about it is a normal practitioner session, including the profile
screen: an edit is written to the device first and the fields still owed to the
server are held in `DoctorDraft.pendingProfile` until it answers. While that
marker is set, a `/auth/me` response refreshes only the trust fields — otherwise
an edit made with no signal would be silently reverted the moment the device
reconnected.

## Localization

The app supports multiple languages:
- English (en)
- Luganda (lg)
- Swahili (sw)
- Runyankore (nyn)

Language selection is available during onboarding and in settings.

## Accessibility

- Text size control: Small → Extra large
- Theme modes: Light, Dark, System
- High-contrast UI elements
- Screen reader compatible

---

Built with ❤️ for patients who can't always find the words.
