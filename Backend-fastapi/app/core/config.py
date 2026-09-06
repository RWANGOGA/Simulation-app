from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    PROJECT_NAME: str = "AtomyBridge Care API"
    VERSION: str = "0.1.0"
    API_V1_STR: str = "/api/v1"
    ENVIRONMENT: str = "development"
    ALLOWED_ORIGINS: str = "*"
    DATABASE_URL: str = "postgresql+psycopg://atomy:atomy123@localhost:5432/atomybridge"
    SECRET_KEY: str = "change-me-in-production"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 8
    MAX_LOGIN_ATTEMPTS: int = 5
    LOGIN_LOCKOUT_SECONDS: int = 300
    # Gates practitioner self-registration. Empty (default) means
    # registration stays open, matching current behavior — set this once
    # real deployment starts, so signup requires knowing the invite code.
    INVITE_CODE: str = ""
    # Groq LLM (free tier) for the /anatomy/ask endpoint. When GROQ_API_KEY
    # is empty, the endpoint still works but skips the LLM and returns the
    # raw retrieved chunks — useful for local dev without burning quota.
    GROQ_API_KEY: str = ""
    GROQ_MODEL: str = "openai/gpt-oss-20b"
    GROQ_BASE_URL: str = "https://api.groq.com/openai/v1"
    GROQ_TIMEOUT_SECONDS: float = 20.0
    model_config = SettingsConfigDict(env_file=".env", case_sensitive=True)

settings = Settings()
