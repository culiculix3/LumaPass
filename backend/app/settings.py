import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Settings:
    environment: str = os.getenv("LUMAPASS_ENV", "demo")
    database_url: str = os.getenv("DATABASE_URL", "")
    apple_app_id: str = os.getenv("APPLE_APP_ID", "app.lumapass.ios")
    pass_type_identifier: str = os.getenv("PASS_TYPE_IDENTIFIER", "")
    apple_team_identifier: str = os.getenv("APPLE_TEAM_IDENTIFIER", "")
    pass_certificate_path: str = os.getenv("PASS_CERTIFICATE_PATH", "")
    pass_private_key_path: str = os.getenv("PASS_PRIVATE_KEY_PATH", "")
    apple_wwdr_certificate_path: str = os.getenv("APPLE_WWDR_CERTIFICATE_PATH", "")
    pass_private_key_passphrase: str = os.getenv("PASS_PRIVATE_KEY_PASSPHRASE", "")
    public_base_url: str = os.getenv("PUBLIC_BASE_URL", "")
    s3_endpoint_url: str = os.getenv("S3_ENDPOINT_URL", "")
    s3_region: str = os.getenv("S3_REGION", "eu-west-1")
    s3_bucket: str = os.getenv("S3_BUCKET", "")
    s3_access_key_id: str = os.getenv("S3_ACCESS_KEY_ID", "")
    s3_secret_access_key: str = os.getenv("S3_SECRET_ACCESS_KEY", "")
    admin_bearer_token: str = os.getenv("ADMIN_BEARER_TOKEN", "")
    allowed_origins: tuple[str, ...] = tuple(
        origin.strip() for origin in os.getenv("ALLOWED_ORIGINS", "").split(",") if origin.strip()
    )
    max_upload_bytes: int = int(os.getenv("MAX_UPLOAD_BYTES", str(5 * 1_024 * 1_024)))
    apple_auth_audience: str = os.getenv(
        "APPLE_AUTH_AUDIENCE", os.getenv("APPLE_APP_ID", "app.lumapass.ios")
    )
    apple_auth_issuer: str = os.getenv("APPLE_AUTH_ISSUER", "https://appleid.apple.com")
    apple_jwks_url: str = os.getenv("APPLE_JWKS_URL", "https://appleid.apple.com/auth/keys")
    apns_key_id: str = os.getenv("APNS_KEY_ID", "")
    apns_team_id: str = os.getenv("APNS_TEAM_ID", "")
    apns_private_key_path: str = os.getenv("APNS_PRIVATE_KEY_PATH", "")
    apns_topic: str = os.getenv("APNS_TOPIC", "")
    apns_use_sandbox: bool = os.getenv("APNS_USE_SANDBOX", "false").lower() == "true"

    def wallet_signing_ready(self) -> bool:
        paths = (
            self.pass_certificate_path,
            self.pass_private_key_path,
            self.apple_wwdr_certificate_path,
        )
        return (
            self.environment == "production"
            and bool(self.pass_type_identifier)
            and bool(self.apple_team_identifier)
            and self.public_base_url.startswith("https://")
            and all(Path(path).is_file() for path in paths)
        )

    def storage_ready(self) -> bool:
        return bool(self.s3_bucket)

    def apple_auth_ready(self) -> bool:
        return bool(self.apple_auth_audience and self.apple_jwks_url)


settings = Settings()
