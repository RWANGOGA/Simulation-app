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
    # Access to the patient-data audit trail is governed by Doctor.access_level
    # (admin only). It used to be a comma-separated email allowlist, which
    # existed only because there was no role to check.
    GROQ_API_KEY: str = Field(default="", validation_alias="GROQ_API_KEY")
    GROQ_MODEL: str = "openai/gpt-oss-20b"
    GROQ_BASE_URL: str = "https://api.groq.com/openai/v1"
    GROQ_TIMEOUT_SECONDS: float = 20.0
    ALLOWED_ORIGINS: str = Field(default="", validation_alias="ALLOWED_ORIGINS")
    # "json" emits one JSON object per line, which is what a log aggregator
    # wants; "plain" stays readable in a developer's terminal.
    LOG_LEVEL: str = Field(default="INFO", validation_alias="LOG_LEVEL")
    LOG_FORMAT: str = Field(default="plain", validation_alias="LOG_FORMAT")
    TRUSTED_HOSTS: str = Field(
        default="atomybridge.com,*.atomybridge.com,api.atomybridge.com,backend-fastapi-linv.onrender.com",
        validation_alias="TRUSTED_HOSTS",
    )
    model_config = SettingsConfigDict(env_file=".env", case_sensitive=True)

settings = Settings()


def warn_on_insecure_defaults() -> None:
    """Called at startup rather than at import.

    Import-time warnings are emitted before logging is configured, so they went
    to the root logger's last-resort handler and lost their timestamp, level
    and request id along with everything else.
    """
    if settings.SECRET_KEY == "change-me-in-production":
        logger.warning(
            "insecure_secret_key",
            extra={
                "detail": "Using the default SECRET_KEY. Set SECRET_KEY before "
                "any deployment — every issued token is forgeable without it."
            },
        )
