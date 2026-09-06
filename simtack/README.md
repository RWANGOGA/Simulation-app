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

The Flutter app integrates with the following backend endpoints:

- **Auth**: `/auth/login`, `/auth/register`, `/auth/me`, `/auth/refresh`, `/auth/logout`
- **Patients**: `/patients/` (create), `/patients/{code}` (read), `/patients/{code}` (update)
- **Triage**: `/triage/` (submit), `/triage/list`, `/triage/stats`, `/triage/history`, `/triage/patient/{code}`, `/triage/{session_id}`, `/triage/{session_id}/decision`
- **Anatomy AI**: `/anatomy/regions`, `/anatomy/ask`, `/anatomy/clear`

See the [root README](../README.md) for full API documentation.

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
