from pathlib import Path
from time import time

import httpx
import jwt

from .settings import settings


def apns_ready() -> bool:
    return bool(
        settings.apns_key_id
        and settings.apns_team_id
        and settings.apns_topic
        and Path(settings.apns_private_key_path).is_file()
    )


async def send_wallet_update(push_tokens: list[str]) -> int:
    if not push_tokens or not apns_ready():
        return 0
    key = Path(settings.apns_private_key_path).read_text(encoding="utf-8")
    provider_token = jwt.encode(
        {"iss": settings.apns_team_id, "iat": int(time())},
        key,
        algorithm="ES256",
        headers={"kid": settings.apns_key_id, "typ": "JWT"},
    )
    host = (
        "https://api.sandbox.push.apple.com"
        if settings.apns_use_sandbox
        else "https://api.push.apple.com"
    )
    delivered = 0
    async with httpx.AsyncClient(http2=True, timeout=httpx.Timeout(8, connect=4)) as client:
        for push_token in push_tokens:
            response = await client.post(
                f"{host}/3/device/{push_token}",
                headers={
                    "authorization": f"bearer {provider_token}",
                    "apns-topic": settings.apns_topic,
                    "apns-push-type": "background",
                    "apns-priority": "5",
                    "content-type": "application/json",
                },
                content=b"{}",
            )
            if response.is_success:
                delivered += 1
            elif response.status_code == 410:
                continue
            else:
                raise RuntimeError(
                    f"Apple Push Notification service respondió con HTTP {response.status_code}."
                )
    return delivered
