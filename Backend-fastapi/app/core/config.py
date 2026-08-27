from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    PROJECT_NAME: str = "AtomyBridge Care API"
    VERSION: str = "0.1.0"
    API_V1_STR: str = "/api/v1"
    DATABASE_URL: str = "postgresql+psycopg://atomy:atomy123@localhost:5432/atomybridge"
    SECRET_KEY: str = "change-me-in-production"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 8
    # Gates practitioner self-registration. Empty (default) means
    # registration stays open, matching current behavior — set this once
    # real deployment starts, so signup requires knowing the invite code.
    INVITE_CODE: str = ""
    model_config = SettingsConfigDict(env_file=".env", case_sensitive=True)

settings = Settings()
