# 🏥 AtomyBridge Care

*"For the body does not consist of one member but of many." — 1 Corinthians 12:14*

**AtomyBridge Care** is an AI-powered, offline-first clinical triage application designed to bridge the communication gap between patients in pain and medical practitioners. It empowers patients to visually map their pain, capture real-time vitals via smartphone cameras, and receive instant, explainable risk assessments.

---

## ️ Architecture Overview

The system is built as a decoupled, full-stack architecture to ensure high performance, security, and scalability.

*   **The Face & Hands (Frontend):** A Flutter application (Android/iOS/Web) that provides an intuitive, 3D interactive interface for patients. It handles edge-computing tasks like PPG (Photoplethysmography) heart-rate extraction directly on the device.
*   **The Brain & Memory (Backend):** A FastAPI (Python) server that processes clinical data, calculates triage risk scores using Explainable AI (SHAP-style logic), and securely stores patient records in a PostgreSQL database.

```text
[ Flutter App (Patient) ]  --(HTTP/JSON)-->  [ FastAPI Server (Doctor) ]  --(SQL)-->  [ PostgreSQL DB ]
       |                                              |
       +-- 3D Body Map (model-viewer)                 +-- Risk Engine
       +-- PPG Camera Vitals                          +-- SHAP Explanations


Project Structure


atomybridge/
├── Backend-fastapi/          # The Python/FastAPI Backend
│   ├── app/
│   │   ├── api/v1/           # API Endpoints (Health, Patients, Triage)
│   │   ├── core/             # Config, Database connection
│   │   ├── crud/             # Database operations
│   │   ├── models/           # SQLAlchemy ORM Models
│   │   ├── schemas/          # Pydantic Data Validation
│   │   └── services/         # Business Logic (Risk Calculation)
│   ├── docker-compose.yml    # PostgreSQL Database setup
│   └── requirements.txt      # Python dependencies
│
├── atomybridge_app/          # The Flutter Frontend
│   ├── lib/
│   │   ├── core/             # API Client, Theme
│   │   └── features/         # UI Screens (Onboarding, BodyMap, Vitals, Review)
│   ├── assets/models/        # 3D GLB Models
│   └── pubspec.yaml          # Flutter dependencies
│
└── README.md                 



Setting up the Backend 


cd Backend-fastapi

# 1. Start the PostgreSQL database
docker compose up -d

# 2. Create and activate a virtual environment
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# 3. Install dependencies
pip install -r requirements.txt

# 4. Initialize the database tables
python -c "from app.core.database import engine, Base; from app.models import Patient, TriageSession; Base.metadata.create_all(bind=engine)"

# 5. Run the server
uvicorn app.main:app --reload --port 8000
or use Docker commands


Setting up the Frontend (The Face)

cd atomybridge_app

# 1. Install Flutter dependencies
flutter pub get

# 2. Run the app on Chrome (or your preferred device)
flutter run -d chrome.  or use emulators
