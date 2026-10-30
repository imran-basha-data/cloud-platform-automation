import pytest
from pydantic import ValidationError

from platform_api.config import Settings

TOKEN = "s3cure-admin-token-value"


def test_defaults_are_safe_for_local_development() -> None:
    settings = Settings()
    assert settings.environment == "dev"
    assert settings.admin_token is None
    assert settings.fail_readiness is False


def test_settings_load_from_environment(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("APP_ENVIRONMENT", "staging")
    monkeypatch.setenv("APP_LOG_LEVEL", "DEBUG")
    monkeypatch.setenv("APP_DEPENDENCY_URL", "http://inventory.internal/health")
    settings = Settings()
    assert settings.environment == "staging"
    assert settings.log_level == "DEBUG"
    assert str(settings.dependency_url) == "http://inventory.internal/health"


@pytest.mark.parametrize(
    "overrides",
    [
        {"environment": "production"},
        {"log_level": "verbose"},
        {"startup_delay_s": -1},
        {"dependency_url": "not a url"},
        {"dependency_timeout_s": 0},
        {"max_work_ms": 0},
    ],
)
def test_invalid_values_fail_fast(overrides: dict[str, object]) -> None:
    with pytest.raises(ValidationError):
        Settings(**overrides)  # type: ignore[arg-type]


def test_prod_requires_a_strong_admin_token() -> None:
    with pytest.raises(ValidationError, match="APP_ADMIN_TOKEN"):
        Settings(environment="prod")
    with pytest.raises(ValidationError, match="APP_ADMIN_TOKEN"):
        Settings(environment="prod", admin_token="short")  # type: ignore[arg-type]


def test_prod_requires_json_logs_and_no_fault_injection() -> None:
    with pytest.raises(ValidationError, match="APP_LOG_FORMAT"):
        Settings(environment="prod", admin_token=TOKEN, log_format="text")  # type: ignore[arg-type]
    with pytest.raises(ValidationError, match="APP_FAIL_READINESS"):
        Settings(environment="prod", admin_token=TOKEN, fail_readiness=True)  # type: ignore[arg-type]


def test_valid_production_settings() -> None:
    settings = Settings(environment="prod", admin_token=TOKEN)  # type: ignore[arg-type]
    assert settings.admin_token is not None
    assert TOKEN not in repr(settings)  # secrets are masked
