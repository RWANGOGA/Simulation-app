from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import Field
import logging

logger = logging.getLogger(__name__)

class Settings(BaseSettings):
    PROJECT_NAME: str = "AtomyBridge Care API"
    VERSION: str = "0.1.0"
    API_V1_STR: str = "/api/v1"
    ENVIRONMENT: str = Field(default="development", validation_alias="ENVIRONMENT")
    DATABASE_URL: str = Field(..., validation_alias="DATABASE_URL")
    SECRET_KEY: str = Field(default="change-me-in-production", min_length=32, validation_alias="SECRET_KEY")
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 15
    MAX_LOGIN_ATTEMPTS: int = 5
    LOGIN_LOCKOUT_SECONDS: int = 300
    INVITE_CODE: str = Field(default="", validation_alias="INVITE_CODE")
    GROQ_API_KEY: str = Field(default="", validation_alias="GROQ_API_KEY")
    GROQ_MODEL: str = "openai/gpt-oss-20b"
    GROQ_BASE_URL: str = "https://api.groq.com/openai/v1"
    GROQ_TIMEOUT_SECONDS: float = 20.0
    ALLOWED_ORIGINS: str = Field(default="", validation_alias="ALLOWED_ORIGINS")
    model_config = SettingsConfigDict(env_file=".env", case_sensitive=True)

settings = Settings()

if settings.SECRET_KEY == "change-me-in-production":
    logger.warning("SECURITY WARNING: Using default SECRET_KEY. Set SECRET_KEY environment variable in production.")
