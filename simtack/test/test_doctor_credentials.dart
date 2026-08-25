/// Shared test practitioner credentials for widget/unit tests.
///
/// Tests must import these instead of hardcoding email/password literals,
/// so the fixture account can be changed in exactly one place (mirrors
/// Backend-fastapi/tests/conftest.py).
const doctorEmail = 'doctor@simtack.com';
const doctorPassword = 'Doctor123!';
