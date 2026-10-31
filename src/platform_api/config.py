"""Validated runtime configuration.

Settings come from environment variables (``APP_*``), as injected by a
Kubernetes ConfigMap and Secret. Invalid configuration fails fast at startup
with a clear message rather than surfacing later as odd runtime behaviour.
"""

from __future__ import annotations

from typing import Literal

from pydantic import Field, HttpUrl, SecretStr, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

from platform_api import __version__


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="APP_", extra="ignore", frozen=True)

    name: str = Field(default="platform-api", min_length=1, max_length=63)
    environment: Literal["dev", "staging", "prod"] = "dev"
    version: str = __version__
    log_level: Literal["DEBUG", "INFO", "WARNING", "ERROR"] = "INFO"
    log_format: Literal["json", "text"] = "json"

    # Optional downstream dependency checked by /readyz (e.g. an internal API).
    dependency_url: HttpUrl | None = None
    dependency_timeout_s: float = Field(default=1.0, gt=0, le=10)

    # Bearer token for admin endpoints. Admin endpoints are disabled when unset.
    admin_token: SecretStr | None = None

    # Simulated warm-up time, used to demonstrate readiness gating.
    startup_delay_s: float = Field(default=0.0, ge=0, le=120)
    # Fault injection: never report ready. Used to prove rollouts stop and roll back.
    fail_readiness: bool = False
    # Upper bound for the synthetic /api/v1/work endpoint.
    max_work_ms: int = Field(default=2000, ge=1, le=10_000)

    @model_validator(mode="after")
    def _production_guardrails(self) -> Settings:
        if self.environment == "prod":
            if self.admin_token is None or len(self.admin_token.get_secret_value()) < 16:
                raise ValueError("APP_ADMIN_TOKEN must be set (16+ characters) in prod")
            if self.log_format != "json":
                raise ValueError("APP_LOG_FORMAT must be 'json' in prod")
            if self.fail_readiness:
                raise ValueError("APP_FAIL_READINESS must not be enabled in prod")
        return self
