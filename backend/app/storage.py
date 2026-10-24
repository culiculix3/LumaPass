import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError
from fastapi import HTTPException

from .settings import settings


def _client():
    if not settings.storage_ready():
        raise HTTPException(
            status_code=503, detail="El almacenamiento privado de archivos no está configurado."
        )
    return boto3.client(
        "s3",
        endpoint_url=settings.s3_endpoint_url or None,
        region_name=settings.s3_region,
        aws_access_key_id=settings.s3_access_key_id or None,
        aws_secret_access_key=settings.s3_secret_access_key or None,
        config=Config(signature_version="s3v4", s3={"addressing_style": "path"}),
    )


def put_private_image(object_key: str, body: bytes) -> None:
    _client().put_object(
        Bucket=settings.s3_bucket,
        Key=object_key,
        Body=body,
        ContentType="image/jpeg",
        CacheControl="private, no-store",
        ServerSideEncryption="AES256",
    )


def signed_image_url(object_key: str) -> str:
    try:
        return _client().generate_presigned_url(
            "get_object",
            Params={
                "Bucket": settings.s3_bucket,
                "Key": object_key,
                "ResponseCacheControl": "private, no-store",
            },
            ExpiresIn=180,
        )
    except (BotoCoreError, ClientError) as error:
        raise HTTPException(
            status_code=503, detail="No se ha podido cargar esta imagen. Inténtalo de nuevo."
        ) from error


def delete_images(object_keys: list[str]) -> None:
    if not object_keys:
        return
    _client().delete_objects(
        Bucket=settings.s3_bucket,
        Delete={"Objects": [{"Key": key} for key in object_keys], "Quiet": True},
    )


def get_private_image(object_key: str) -> bytes:
    try:
        result = _client().get_object(Bucket=settings.s3_bucket, Key=object_key)
        return result["Body"].read(settings.max_upload_bytes + 1)
    except (BotoCoreError, ClientError, KeyError) as error:
        raise HTTPException(
            status_code=503, detail="No se ha podido recuperar el arte privado del pase."
        ) from error
