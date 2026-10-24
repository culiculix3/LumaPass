import base64
import binascii
import hashlib
import secrets
from datetime import UTC, datetime
from typing import Annotated, Literal
from uuid import UUID, uuid4

import httpx
from fastapi import (
    APIRouter,
    Depends,
    File,
    Form,
    Header,
    HTTPException,
    Query,
    Response,
    UploadFile,
)
from psycopg import Connection
from psycopg.errors import DatabaseError, UniqueViolation
from pydantic import BaseModel, ConfigDict, Field, field_validator

from . import apns
from .auth import authenticated_user, optional_authenticated_user, require_admin
from .database import get_connection, require_ready_connection
from .settings import settings
from .storage import delete_images, get_private_image, put_private_image, signed_image_url
from .validation import dominant_colors, normalize_image, safe_text, validate_barcode
from .wallet import create_pkpass, new_pass_identity

router = APIRouter(prefix="/api/v1")
apple_wallet_router = APIRouter(prefix="/apple-wallet/v1")
UserId = Annotated[str, Depends(authenticated_user)]
OptionalUserId = Annotated[str | None, Depends(optional_authenticated_user)]
DB = Annotated[Connection, Depends(get_connection)]
ASSET_CATEGORIES = {
    "Minimalista",
    "Abstracto",
    "Neón",
    "Elegante",
    "Retro",
    "Naturaleza",
    "Arte",
    "Tecnología",
}

EDITORIAL_COLLECTION = [
    {
        "id": "aurora",
        "title": "Aurora",
        "description": "Luz suave sobre el horizonte.",
        "category": "Abstracto",
        "tags": ["gradiente", "noche"],
        "license": "CC0 1.0",
        "backgroundHex": "40356F",
        "foregroundHex": "FFFFFF",
        "creator": "LumaPass Studio",
        "uses": 1482,
    },
    {
        "id": "atelier",
        "title": "Atelier",
        "description": "Un lienzo limpio y contemporáneo.",
        "category": "Minimalista",
        "tags": ["limpio", "diseño"],
        "license": "CC0 1.0",
        "backgroundHex": "243A38",
        "foregroundHex": "FFFFFF",
        "creator": "LumaPass Studio",
        "uses": 1206,
    },
    {
        "id": "afterglow",
        "title": "Afterglow",
        "description": "Color eléctrico, líneas calmadas.",
        "category": "Neón",
        "tags": ["neón", "noche"],
        "license": "CC0 1.0",
        "backgroundHex": "54245F",
        "foregroundHex": "FFFFFF",
        "creator": "LumaPass Studio",
        "uses": 982,
    },
    {
        "id": "monogram",
        "title": "Monograma",
        "description": "Elegancia serena, sin excesos.",
        "category": "Elegante",
        "tags": ["premium", "editorial"],
        "license": "CC0 1.0",
        "backgroundHex": "3A332E",
        "foregroundHex": "FFFFFF",
        "creator": "LumaPass Studio",
        "uses": 844,
    },
    {
        "id": "sunroom",
        "title": "Sunroom",
        "description": "Una tarde dorada en calma.",
        "category": "Naturaleza",
        "tags": ["luz", "cálido"],
        "license": "CC0 1.0",
        "backgroundHex": "714C31",
        "foregroundHex": "FFFFFF",
        "creator": "LumaPass Studio",
        "uses": 729,
    },
    {
        "id": "signal",
        "title": "Señal",
        "description": "Contraste preciso con energía retro.",
        "category": "Retro",
        "tags": ["geométrico", "color"],
        "license": "CC0 1.0",
        "backgroundHex": "254064",
        "foregroundHex": "FFFFFF",
        "creator": "LumaPass Studio",
        "uses": 691,
    },
    {
        "id": "silk",
        "title": "Seda",
        "description": "Una composición suave y sofisticada.",
        "category": "Arte",
        "tags": ["textura", "arte"],
        "license": "CC0 1.0",
        "backgroundHex": "683B50",
        "foregroundHex": "FFFFFF",
        "creator": "LumaPass Studio",
        "uses": 614,
    },
    {
        "id": "orbit",
        "title": "Órbita",
        "description": "Una paleta cósmica y nítida.",
        "category": "Tecnología",
        "tags": ["digital", "espacio"],
        "license": "CC0 1.0",
        "backgroundHex": "273758",
        "foregroundHex": "FFFFFF",
        "creator": "LumaPass Studio",
        "uses": 560,
    },
]


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


class PassContent(StrictModel):
    type: Literal["generic", "membership", "loyalty", "coupon", "ticket"]
    title: str = Field(min_length=1, max_length=100)
    organization: str = Field(min_length=1, max_length=100)
    primaryLabel: str = Field(default="", max_length=100)
    primaryValue: str = Field(default="", max_length=100)
    secondaryLabel: str = Field(default="", max_length=100)
    secondaryValue: str = Field(default="", max_length=100)
    additionalLabel: str = Field(default="", max_length=100)
    additionalValue: str = Field(default="", max_length=100)
    barcodeValue: str = Field(default="", max_length=512)
    barcodeKind: Literal["qr", "code128"]
    backgroundHex: str
    foregroundHex: str
    expiresAt: datetime | None = None
    image: str | None = None
    draftId: UUID | None = None

    @field_validator("image")
    @classmethod
    def check_image_size(cls, value: str | None) -> str | None:
        if value and len(value) > ((settings.max_upload_bytes + 2) // 3) * 4:
            raise ValueError("La imagen codificada supera el tamaño máximo permitido.")
        return value


class FavoriteRequest(StrictModel):
    isFavorite: bool


class ReportRequest(StrictModel):
    reason: Literal["illegal", "offensive", "copyright", "fraud", "other"]
    detail: str = Field(default="", max_length=500)


class RegistrationRequest(StrictModel):
    pushToken: str = Field(min_length=16, max_length=512, pattern=r"^[0-9a-fA-F]+$")


class ModerationRequest(StrictModel):
    status: Literal["approved", "hidden", "rejected"]


def take_rate_limit(connection: Connection, user_id: str, action: str, limit: int) -> None:
    row = connection.execute(
        """
        INSERT INTO rate_limit_buckets (user_id, action, bucket_start, uses)
        VALUES (%s, %s, date_trunc('minute', now()), 1)
        ON CONFLICT (user_id, action, bucket_start)
        DO UPDATE SET uses = rate_limit_buckets.uses + 1
        WHERE rate_limit_buckets.uses < %s
        RETURNING uses
        """,
        (user_id, action, limit),
    ).fetchone()
    if row is None:
        raise HTTPException(
            status_code=429, detail="Has alcanzado el límite. Inténtalo dentro de un minuto."
        )


def _normalize_content(content: PassContent) -> dict:
    result = content.model_dump(mode="json")
    result["barcodeKind"] = "QR" if result["barcodeKind"] == "qr" else "Code128"
    try:
        for name in (
            "title",
            "organization",
            "primaryLabel",
            "primaryValue",
            "secondaryLabel",
            "secondaryValue",
            "additionalLabel",
            "additionalValue",
        ):
            result[name] = safe_text(
                result[name],
                field_name=name,
                optional=name not in {"title", "organization"},
            )
        validate_barcode(result["barcodeValue"], result["barcodeKind"])
    except ValueError as error:
        raise HTTPException(status_code=422, detail=str(error)) from error
    return result


def _pass_token_matches(presented: str | None, stored_hash: str) -> bool:
    if presented is None:
        return False
    return secrets.compare_digest(
        hashlib.sha256(presented.encode("utf-8")).digest(),
        bytes.fromhex(stored_hash),
    )


@router.get("/health/live")
def live_check() -> dict[str, str]:
    return {"status": "ok", "mode": settings.environment}


@router.get("/health/ready")
def ready_check() -> dict[str, str]:
    connection_pool = require_ready_connection()
    with connection_pool.connection(timeout=3) as connection:
        connection.execute("SELECT 1")
    return {
        "status": "ready",
        "mode": settings.environment,
        "walletSigning": "ready" if settings.wallet_signing_ready() else "demo",
        "privateImageStorage": "ready" if settings.storage_ready() else "not-configured",
    }


@router.get("/gallery/templates")
def editorial_templates() -> list[dict]:
    return EDITORIAL_COLLECTION


@router.get("/community/assets")
def browse_assets(
    connection: DB,
    user_id: OptionalUserId,
    query: str = "",
    category: str | None = None,
    order: Literal["new", "trending"] = "trending",
    offset: int = 0,
    limit: int = 30,
) -> dict:
    if category is not None and category not in ASSET_CATEGORIES:
        raise HTTPException(status_code=422, detail="La categoría de la galería no existe.")
    query = " ".join(query.split())
    if len(query) > 80:
        raise HTTPException(status_code=422, detail="La búsqueda supera 80 caracteres.")
    if offset < 0 or limit < 1 or limit > 50:
        raise HTTPException(status_code=422, detail="La página solicitada no es válida.")
    result = connection.execute(
        """
        SELECT a.id, a.author_id, a.title, a.description, a.category, a.tags,
               a.dominant_colors, a.license, a.use_count, a.object_key, a.created_at
        FROM community_assets AS a
        WHERE a.status = 'approved'
          AND (%s = '' OR a.category = %s)
          AND (%s = '' OR concat_ws(' ', a.title, a.description, array_to_string(a.tags, ' '))
                                ILIKE '%%' || %s || '%%')
          AND NOT EXISTS (
              SELECT 1 FROM blocked_users b
              WHERE b.blocker_id = %s AND b.blocked_id = a.author_id
          )
        ORDER BY
          CASE WHEN %s = 'trending' THEN a.use_count END DESC NULLS LAST,
          CASE WHEN %s = 'new' THEN a.created_at END DESC NULLS LAST
        OFFSET %s LIMIT %s
        """,
        (category or "", category or "", query, query, user_id, order, order, offset, limit),
    ).fetchall()
    return {
        "items": [
            {
                "id": str(item["id"]),
                "creatorId": str(item["author_id"]),
                "title": item["title"],
                "description": item["description"],
                "category": item["category"],
                "tags": item["tags"],
                "dominantColors": item["dominant_colors"],
                "license": item["license"],
                "uses": item["use_count"],
                "createdAt": item["created_at"].isoformat(),
                "imageURL": signed_image_url(item["object_key"]),
            }
            for item in result
        ],
        "nextOffset": offset + len(result) if len(result) == limit else None,
    }


@router.get("/community/collections")
def community_collections() -> dict[str, list[dict]]:
    return {"editorial": EDITORIAL_COLLECTION, "categories": sorted(ASSET_CATEGORIES)}


@router.post("/community/assets", status_code=202)
async def upload_asset(
    user_id: UserId,
    connection: DB,
    title: Annotated[str, Form(max_length=80)],
    description: Annotated[str, Form(max_length=240)],
    category: Annotated[str, Form()],
    license: Annotated[str, Form()],
    rights_confirmed: Annotated[bool, Form()],
    file: Annotated[UploadFile, File()],
    tags: Annotated[str, Form()] = "",
) -> dict:
    if not rights_confirmed:
        raise HTTPException(
            status_code=422, detail="Confirma que tienes derecho a compartir este fondo."
        )
    if category not in ASSET_CATEGORIES:
        raise HTTPException(status_code=422, detail="La categoría seleccionada no existe.")
    if license not in {"CC0 1.0", "CC BY 4.0"}:
        raise HTTPException(status_code=422, detail="Selecciona una licencia CC0 1.0 o CC BY 4.0.")
    try:
        title = safe_text(title, field_name="El título", optional=False)
        description = safe_text(description, field_name="La descripción")
        tags_list = [
            safe_text(tag, field_name="La etiqueta") for tag in tags.split(",") if tag.strip()
        ]
        if len(tags_list) > 8 or any(len(tag) > 24 for tag in tags_list):
            raise ValueError("Añade hasta ocho etiquetas de 24 caracteres como máximo.")
    except ValueError as error:
        raise HTTPException(status_code=422, detail=str(error)) from error
    if file.content_type not in {"image/jpeg", "image/png", "image/webp"}:
        raise HTTPException(status_code=415, detail="Sube una imagen JPEG, PNG o WebP.")
    image_bytes = await file.read(settings.max_upload_bytes + 1)
    await file.close()
    try:
        processed, width, height = normalize_image(image_bytes, settings.max_upload_bytes)
    except ValueError as error:
        raise HTTPException(status_code=422, detail=str(error)) from error
    take_rate_limit(connection, user_id, "community_upload", 8)
    asset_id = uuid4()
    object_key = f"community/pending/{asset_id}.jpg"
    put_private_image(object_key, processed)
    try:
        connection.execute(
            """
            INSERT INTO community_assets
                (id, author_id, title, description, category, tags, dominant_colors,
                 license, rights_confirmed, object_key)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, true, %s)
            """,
            (
                asset_id,
                user_id,
                title,
                description,
                category,
                tags_list,
                dominant_colors(processed),
                license,
                object_key,
            ),
        )
    except DatabaseError:
        delete_images([object_key])
        raise
    return {
        "id": str(asset_id),
        "status": "pending",
        "dimensions": {"width": width, "height": height},
        "message": "El fondo se ha enviado de forma privada a revisión antes de su publicación.",
    }


@router.post("/community/assets/{asset_id}/favorite")
def favorite_asset(asset_id: UUID, body: FavoriteRequest, user_id: UserId, connection: DB) -> dict:
    take_rate_limit(connection, user_id, "favorite", 120)
    exists = connection.execute(
        "SELECT 1 FROM community_assets WHERE id = %s AND status = 'approved'",
        (asset_id,),
    ).fetchone()
    if exists is None:
        raise HTTPException(status_code=404, detail="No se encuentra el fondo publicado.")
    if body.isFavorite:
        connection.execute(
            "INSERT INTO favorites (user_id, asset_id) VALUES (%s, %s) ON CONFLICT DO NOTHING",
            (user_id, asset_id),
        )
    else:
        connection.execute(
            "DELETE FROM favorites WHERE user_id = %s AND asset_id = %s",
            (user_id, asset_id),
        )
    return {"assetId": str(asset_id), "isFavorite": body.isFavorite}


@router.post("/community/assets/{asset_id}/use")
def use_asset(
    asset_id: UUID,
    user_id: UserId,
    connection: DB,
) -> dict:
    take_rate_limit(connection, user_id, "community_apply", 60)
    row = connection.execute(
        """
        UPDATE community_assets SET use_count = use_count + 1
        WHERE id = %s AND status = 'approved'
        RETURNING use_count
        """,
        (asset_id,),
    ).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="No se encuentra este fondo aprobado.")
    return {"useCount": row["use_count"]}


@router.get("/community/favorites")
def list_favorites(user_id: UserId, connection: DB) -> list[str]:
    rows = connection.execute(
        "SELECT asset_id FROM favorites WHERE user_id = %s ORDER BY created_at DESC",
        (user_id,),
    ).fetchall()
    return [str(row["asset_id"]) for row in rows]


@router.post("/community/assets/{asset_id}/report", status_code=201)
def report_asset(
    asset_id: UUID,
    body: ReportRequest,
    user_id: UserId,
    connection: DB,
) -> dict:
    take_rate_limit(connection, user_id, "community_report", 20)
    exists = connection.execute(
        "SELECT 1 FROM community_assets WHERE id = %s AND status != 'rejected'",
        (asset_id,),
    ).fetchone()
    if exists is None:
        raise HTTPException(status_code=404, detail="No se encuentra este diseño.")
    try:
        row = connection.execute(
            """
            INSERT INTO content_reports (reporter_id, asset_id, reason, detail)
            VALUES (%s, %s, %s, %s)
            RETURNING id
            """,
            (user_id, asset_id, body.reason, body.detail),
        ).fetchone()
    except UniqueViolation as error:
        raise HTTPException(
            status_code=409, detail="Ya has enviado un reporte para este diseño."
        ) from error
    return {"reportId": str(row["id"]), "status": "pending"}


@router.post("/community/assets/{asset_id}/block-author")
def block_asset_author(asset_id: UUID, user_id: UserId, connection: DB) -> dict:
    take_rate_limit(connection, user_id, "block_author", 30)
    author = connection.execute(
        "SELECT author_id FROM community_assets WHERE id = %s AND status = 'approved'",
        (asset_id,),
    ).fetchone()
    if author is None:
        raise HTTPException(status_code=404, detail="No se encuentra este diseño.")
    if str(author["author_id"]) == user_id:
        raise HTTPException(status_code=422, detail="No puedes bloquear tu propia cuenta.")
    connection.execute(
        "INSERT INTO blocked_users (blocker_id, blocked_id) VALUES (%s, %s) ON CONFLICT DO NOTHING",
        (user_id, author["author_id"]),
    )
    return {"blocked": True}


@router.post("/drafts", status_code=201)
def save_private_draft(content: PassContent, user_id: UserId, connection: DB) -> dict:
    draft_id = content.draftId or uuid4()
    normalized = _normalize_content(content)
    image = normalized.pop("image", None)
    image_key = None
    if image:
        try:
            image_bytes = base64.b64decode(image, validate=True)
            processed, _, _ = normalize_image(image_bytes, settings.max_upload_bytes)
        except (ValueError, binascii.Error) as error:
            raise HTTPException(
                status_code=422, detail="El arte del borrador no es una imagen válida."
            ) from error
        image_key = f"private-drafts/{user_id}/{uuid4()}.jpg"
        put_private_image(image_key, processed)
    try:
        connection.execute(
            """
            INSERT INTO private_drafts (id, user_id, content, image_object_key)
            VALUES (%s, %s, %s::jsonb, %s)
            """,
            (draft_id, user_id, content.model_dump_json(exclude={"image"}), image_key),
        )
    except DatabaseError:
        if image_key:
            delete_images([image_key])
        raise
    return {"id": str(draft_id), "updatedAt": datetime.now(UTC).isoformat()}


@router.get("/drafts")
def list_private_drafts(user_id: UserId, connection: DB) -> list[dict]:
    rows = connection.execute(
        """
        SELECT id, content, updated_at FROM private_drafts
        WHERE user_id = %s ORDER BY updated_at DESC LIMIT 100
        """,
        (user_id,),
    ).fetchall()
    return [
        {
            "id": str(row["id"]),
            "content": row["content"],
            "updatedAt": row["updated_at"].isoformat(),
        }
        for row in rows
    ]


@router.put("/drafts/{draft_id}")
async def update_private_draft(
    draft_id: UUID,
    content: PassContent,
    user_id: UserId,
    connection: DB,
) -> dict:
    take_rate_limit(connection, user_id, "private_draft", 120)
    _normalize_content(content)
    prior = connection.execute(
        "SELECT image_object_key FROM private_drafts WHERE id = %s AND user_id = %s",
        (draft_id, user_id),
    ).fetchone()
    old_key = prior["image_object_key"] if prior else None
    new_key = None
    if content.image:
        try:
            image = base64.b64decode(content.image, validate=True)
            processed, _, _ = normalize_image(image, settings.max_upload_bytes)
        except (ValueError, binascii.Error) as error:
            raise HTTPException(
                status_code=422, detail="El arte del borrador no es una imagen válida."
            ) from error
        new_key = f"private-drafts/{user_id}/{uuid4()}.jpg"
        put_private_image(new_key, processed)

    payload = content.model_dump_json(exclude={"image"})
    try:
        connection.execute(
            """
            INSERT INTO private_drafts (id, user_id, content, image_object_key)
            VALUES (%s, %s, %s::jsonb, %s)
            ON CONFLICT (user_id, id)
            DO UPDATE SET content = EXCLUDED.content,
                          image_object_key = EXCLUDED.image_object_key,
                          updated_at = now()
            """,
            (draft_id, user_id, payload, new_key),
        )
        updated_passes = connection.execute(
            """
            UPDATE issued_passes
            SET content = %s::jsonb,
                image_object_key = %s,
                updated_at = now(),
                update_tag = GREATEST(update_tag + 1, floor(extract(epoch from now()))::bigint)
            WHERE user_id = %s AND draft_id = %s AND revoked_at IS NULL
            RETURNING pass_type_identifier, serial_number
            """,
            (payload, new_key, user_id, draft_id),
        ).fetchall()
        connection.commit()
    except DatabaseError:
        if new_key:
            delete_images([new_key])
        raise
    if old_key and old_key != new_key:
        delete_images([old_key])

    notifications = "no-installed-passes"
    if updated_passes:
        push_rows = connection.execute(
            """
            SELECT DISTINCT d.push_token
            FROM wallet_devices AS d
            JOIN issued_passes AS p USING (pass_type_identifier, serial_number)
            WHERE p.user_id = %s AND p.draft_id = %s AND p.revoked_at IS NULL
            """,
            (user_id, draft_id),
        ).fetchall()
        push_tokens = [row["push_token"] for row in push_rows]
        if push_tokens and not apns.apns_ready():
            notifications = "APNs no está configurado; no se han enviado avisos de actualización."
        elif push_tokens:
            try:
                delivered = await apns.send_wallet_update(push_tokens)
                notifications = f"{delivered} aviso(s) de actualización enviados."
            except (RuntimeError, OSError, httpx.HTTPError) as error:
                notifications = f"Los cambios se guardaron, pero no se enviaron los avisos: {error}"
    return {
        "id": str(draft_id),
        "updatedPasses": len(updated_passes),
        "walletNotifications": notifications,
        "updatedAt": datetime.now(UTC).isoformat(),
    }


@router.delete("/drafts/{draft_id}", status_code=204)
def delete_private_draft(draft_id: UUID, user_id: UserId, connection: DB) -> Response:
    row = connection.execute(
        "DELETE FROM private_drafts WHERE id = %s AND user_id = %s RETURNING image_object_key",
        (draft_id, user_id),
    ).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="No se encuentra el borrador.")
    if row["image_object_key"]:
        delete_images([row["image_object_key"]])
    return Response(status_code=204)


@router.post("/passes")
def issue_pass(content: PassContent, user_id: UserId, connection: DB) -> Response:
    take_rate_limit(connection, user_id, "issue_pass", 10)
    normalized = _normalize_content(content)
    normalized["image"] = content.image
    draft_id = content.draftId or uuid4()
    serial_number, authentication_token = new_pass_identity()
    updated_at = datetime.now(UTC).replace(microsecond=0)
    image_key = None
    if content.image:
        try:
            image_bytes = base64.b64decode(content.image, validate=True)
            normalized_image, _, _ = normalize_image(image_bytes, settings.max_upload_bytes)
        except (ValueError, binascii.Error) as error:
            raise HTTPException(
                status_code=422, detail="El arte del pase no es una imagen válida."
            ) from error
        normalized["image"] = base64.b64encode(normalized_image).decode("ascii")
        image_key = f"issued-passes/{user_id}/{serial_number}.jpg"
        put_private_image(image_key, normalized_image)
    signed_pass = create_pkpass(
        normalized,
        serial_number=serial_number,
        authentication_token=authentication_token,
        updated_at=updated_at,
    )
    payload = content.model_dump_json(exclude={"image"})
    try:
        connection.execute(
            """
            INSERT INTO private_drafts (id, user_id, content, image_object_key)
            VALUES (%s, %s, %s::jsonb, %s)
            ON CONFLICT (user_id, id)
            DO UPDATE SET content = EXCLUDED.content,
                          image_object_key = EXCLUDED.image_object_key,
                          updated_at = now()
            """,
            (draft_id, user_id, payload, image_key),
        )
        connection.execute(
            """
            INSERT INTO issued_passes
                (pass_type_identifier, serial_number, user_id, draft_id,
                 authentication_token_hash, content, image_object_key, updated_at, update_tag)
            VALUES (%s, %s, %s, %s, %s, %s::jsonb, %s, %s, %s)
            """,
            (
                settings.pass_type_identifier,
                serial_number,
                user_id,
                draft_id,
                hashlib.sha256(authentication_token.encode("utf-8")).hexdigest(),
                payload,
                image_key,
                updated_at,
                int(updated_at.timestamp()),
            ),
        )
    except DatabaseError:
        if image_key:
            delete_images([image_key])
        raise
    return Response(
        content=signed_pass,
        media_type="application/vnd.apple.pkpass",
        headers={
            "Content-Disposition": 'attachment; filename="lumapass.pkpass"',
            "Cache-Control": "private, no-store, no-cache, max-age=0",
            "X-Content-Type-Options": "nosniff",
        },
    )


@router.delete("/account", status_code=200)
async def delete_account(user_id: UserId, connection: DB) -> dict:
    rows = connection.execute(
        """
        SELECT object_key AS key FROM community_assets WHERE author_id = %s
        UNION ALL
        SELECT image_object_key AS key FROM private_drafts WHERE user_id = %s
        UNION ALL
        SELECT image_object_key AS key FROM issued_passes WHERE user_id = %s
        """,
        (user_id, user_id, user_id),
    ).fetchall()
    push_rows = connection.execute(
        """
        SELECT DISTINCT d.push_token FROM wallet_devices AS d
        JOIN issued_passes AS p USING (pass_type_identifier, serial_number)
        WHERE p.user_id = %s AND p.revoked_at IS NULL
        """,
        (user_id,),
    ).fetchall()
    connection.execute(
        """
        UPDATE issued_passes
        SET revoked_at = now(),
            content = '{
                "type":"generic","title":"Pase retirado","organization":"LumaPass",
                "primaryLabel":"ESTADO","primaryValue":"Cuenta eliminada",
                "barcodeValue":"","barcodeKind":"QR",
                "backgroundHex":"40356F","foregroundHex":"FFFFFF","revoked":true
            }'::jsonb,
            image_object_key = NULL,
            updated_at = now(),
            update_tag = GREATEST(update_tag + 1, floor(extract(epoch from now()))::bigint)
        WHERE user_id = %s AND revoked_at IS NULL
        """,
        (user_id,),
    )
    deleted = connection.execute(
        "DELETE FROM users WHERE id = %s RETURNING id", (user_id,)
    ).fetchone()
    if deleted is None:
        raise HTTPException(status_code=404, detail="No se encuentra la cuenta.")
    connection.commit()
    delete_images([row["key"] for row in rows if row["key"]])
    notifications = "no-installed-passes"
    push_tokens = [row["push_token"] for row in push_rows]
    if push_tokens and not apns.apns_ready():
        notifications = "APNs no está configurado; los pases instalados no se han notificado."
    elif push_tokens:
        try:
            delivered = await apns.send_wallet_update(push_tokens)
            notifications = f"{delivered} aviso(s) de retirada enviados."
        except (RuntimeError, OSError, httpx.HTTPError) as error:
            notifications = f"La cuenta se eliminó, pero no se enviaron los avisos: {error}"
    return {"status": "deleted", "walletNotifications": notifications}


def _admin_authorization(authorization: str | None = Header(default=None)) -> None:
    require_admin(authorization)


@router.get("/admin/reports", dependencies=[Depends(_admin_authorization)])
def admin_reports(
    connection: DB,
    status_filter: Literal["pending", "reviewed", "actioned", "dismissed"] = "pending",
) -> list[dict]:
    rows = connection.execute(
        """
        SELECT r.id, r.asset_id, r.reason, r.detail, r.status, r.created_at,
               a.title AS asset_title, a.category
        FROM content_reports r
        JOIN community_assets a ON a.id = r.asset_id
        WHERE r.status = %s ORDER BY r.created_at ASC LIMIT 100
        """,
        (status_filter,),
    ).fetchall()
    return [
        {
            "id": str(row["id"]),
            "assetId": str(row["asset_id"]),
            "reason": row["reason"],
            "detail": row["detail"],
            "status": row["status"],
            "createdAt": row["created_at"].isoformat(),
            "assetTitle": row["asset_title"],
            "category": row["category"],
        }
        for row in rows
    ]


@router.get("/admin/assets", dependencies=[Depends(_admin_authorization)])
def admin_assets(
    connection: DB, status_filter: Literal["pending", "approved", "hidden", "rejected"] = "pending"
) -> list[dict]:
    rows = connection.execute(
        """
        SELECT id, author_id, title, description, category, license, status, created_at
        FROM community_assets WHERE status = %s ORDER BY created_at LIMIT 100
        """,
        (status_filter,),
    ).fetchall()
    return [
        {
            "id": str(row["id"]),
            "authorId": str(row["author_id"]),
            "title": row["title"],
            "description": row["description"],
            "category": row["category"],
            "license": row["license"],
            "status": row["status"],
            "createdAt": row["created_at"].isoformat(),
        }
        for row in rows
    ]


@router.put("/admin/assets/{asset_id}", dependencies=[Depends(_admin_authorization)])
def review_asset(
    asset_id: UUID,
    body: ModerationRequest,
    connection: DB,
) -> dict:
    row = connection.execute(
        """
        UPDATE community_assets
        SET status = %s, moderated_at = now()
        WHERE id = %s RETURNING id, status
        """,
        (body.status, asset_id),
    ).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="No se encuentra el fondo.")
    return {"id": str(row["id"]), "status": row["status"]}


@router.put("/admin/reports/{report_id}", dependencies=[Depends(_admin_authorization)])
def review_report(
    report_id: UUID,
    status_filter: Literal["reviewed", "actioned", "dismissed"],
    connection: DB,
) -> dict:
    with connection.transaction():
        row = connection.execute(
            """
            UPDATE content_reports SET status = %s, moderated_at = now()
            WHERE id = %s RETURNING asset_id
            """,
            (status_filter, report_id),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="No se encuentra el reporte.")
        if status_filter == "actioned":
            connection.execute(
                "UPDATE community_assets SET status = 'hidden', moderated_at = now() WHERE id = %s",
                (row["asset_id"],),
            )
    return {"id": str(report_id), "status": status_filter}


@apple_wallet_router.get(
    "/devices/{device_id}/registrations/{pass_type}",
    response_model=None,
)
def registered_updates(
    device_id: str,
    pass_type: str,
    connection: DB,
    authorization: Annotated[str | None, Header(alias="Authorization")] = None,
    passes_updated_since: Annotated[str | None, Query(alias="passesUpdatedSince")] = None,
) -> dict | Response:
    if pass_type != settings.pass_type_identifier:
        raise HTTPException(status_code=404, detail="No se encuentra este tipo de pase.")
    try:
        update_after = int(passes_updated_since or "0")
    except ValueError as error:
        raise HTTPException(
            status_code=400, detail="El número de actualización no es válido."
        ) from error
    token = _wallet_authorization_token(authorization)
    if token is None:
        raise HTTPException(
            status_code=401, detail="El pase no está autorizado para comprobar actualizaciones."
        )
    authenticated_device = connection.execute(
        """
        SELECT 1 FROM wallet_devices d
        JOIN issued_passes p USING (pass_type_identifier, serial_number)
        WHERE d.device_library_identifier = %s AND d.pass_type_identifier = %s
          AND p.authentication_token_hash = %s
        LIMIT 1
        """,
        (device_id, pass_type, hashlib.sha256(token.encode("utf-8")).hexdigest()),
    ).fetchone()
    if authenticated_device is None:
        raise HTTPException(
            status_code=401, detail="El pase no está autorizado para comprobar actualizaciones."
        )
    rows = connection.execute(
        """
        SELECT p.serial_number, p.update_tag
        FROM wallet_devices d
        JOIN issued_passes p USING (pass_type_identifier, serial_number)
        WHERE d.device_library_identifier = %s AND d.pass_type_identifier = %s
          AND p.update_tag > %s
        ORDER BY p.update_tag ASC
        """,
        (device_id, pass_type, update_after),
    ).fetchall()
    if not rows:
        return Response(status_code=204)
    return {
        "serialNumbers": [row["serial_number"] for row in rows],
        "lastUpdated": str(max(row["update_tag"] for row in rows)),
    }


@apple_wallet_router.post(
    "/devices/{device_id}/registrations/{pass_type}/{serial_number}", status_code=201
)
def register_wallet_device(
    device_id: str,
    pass_type: str,
    serial_number: str,
    body: RegistrationRequest,
    connection: DB,
    authorization: Annotated[str | None, Header(alias="Authorization")] = None,
) -> Response:
    if pass_type != settings.pass_type_identifier:
        raise HTTPException(status_code=404, detail="No se encuentra este tipo de pase.")
    pass_row = connection.execute(
        """
        SELECT authentication_token_hash, revoked_at
        FROM issued_passes WHERE pass_type_identifier = %s AND serial_number = %s
        """,
        (pass_type, serial_number),
    ).fetchone()
    if pass_row is None or pass_row["revoked_at"] is not None:
        raise HTTPException(status_code=404, detail="No se encuentra el pase.")
    presented = _wallet_authorization_token(authorization)
    if not _pass_token_matches(presented, pass_row["authentication_token_hash"]):
        raise HTTPException(status_code=401, detail="El pase no está autorizado para registrarse.")
    was_registered = (
        connection.execute(
            """
        SELECT 1 FROM wallet_devices
        WHERE device_library_identifier = %s AND pass_type_identifier = %s AND serial_number = %s
        """,
            (device_id, pass_type, serial_number),
        ).fetchone()
        is not None
    )
    connection.execute(
        """
        INSERT INTO wallet_devices
            (device_library_identifier, pass_type_identifier, serial_number, push_token)
        VALUES (%s, %s, %s, %s)
        ON CONFLICT (device_library_identifier, pass_type_identifier, serial_number)
        DO UPDATE SET push_token = EXCLUDED.push_token, registered_at = now()
        """,
        (device_id, pass_type, serial_number, body.pushToken),
    )
    return Response(status_code=200 if was_registered else 201)


@apple_wallet_router.delete(
    "/devices/{device_id}/registrations/{pass_type}/{serial_number}", status_code=200
)
def unregister_wallet_device(
    device_id: str,
    pass_type: str,
    serial_number: str,
    connection: DB,
    authorization: Annotated[str | None, Header(alias="Authorization")] = None,
) -> Response:
    pass_row = connection.execute(
        """
        SELECT authentication_token_hash
        FROM issued_passes
        WHERE pass_type_identifier = %s AND serial_number = %s
        """,
        (pass_type, serial_number),
    ).fetchone()
    if pass_row is None:
        return Response(status_code=200)
    presented = _wallet_authorization_token(authorization)
    if not _pass_token_matches(presented, pass_row["authentication_token_hash"]):
        raise HTTPException(
            status_code=401, detail="El pase no está autorizado para eliminar este registro."
        )
    connection.execute(
        """
        DELETE FROM wallet_devices
        WHERE device_library_identifier = %s AND pass_type_identifier = %s AND serial_number = %s
        """,
        (device_id, pass_type, serial_number),
    )
    return Response(status_code=200)


@apple_wallet_router.get("/passes/{pass_type}/{serial_number}")
def refresh_wallet_pass(
    pass_type: str,
    serial_number: str,
    connection: DB,
    authorization: Annotated[str | None, Header(alias="Authorization")] = None,
) -> Response:
    row = connection.execute(
        """
        SELECT authentication_token_hash, content, image_object_key, updated_at, revoked_at
        FROM issued_passes WHERE pass_type_identifier = %s AND serial_number = %s
        """,
        (pass_type, serial_number),
    ).fetchone()
    if row is None or pass_type != settings.pass_type_identifier:
        raise HTTPException(status_code=404, detail="Este pase ya no está disponible.")
    presented = _wallet_authorization_token(authorization)
    if not _pass_token_matches(presented, row["authentication_token_hash"]):
        raise HTTPException(status_code=401, detail="El pase no está autorizado para actualizarse.")
    content = dict(row["content"])
    content["barcodeKind"] = "QR" if content.get("barcodeKind", "qr").lower() == "qr" else "Code128"
    if row["image_object_key"]:
        content["image"] = base64.b64encode(get_private_image(row["image_object_key"])).decode(
            "ascii"
        )
    if row["revoked_at"] is not None:
        content["revoked"] = True
        content["title"] = "Pase retirado"
        content["organization"] = "LumaPass"
        content["barcodeValue"] = ""
        content["primaryValue"] = "Cuenta eliminada"
    token = presented
    result = create_pkpass(
        content,
        serial_number=serial_number,
        authentication_token=token,
        updated_at=row["updated_at"],
    )
    return Response(
        content=result,
        media_type="application/vnd.apple.pkpass",
        headers={
            "Cache-Control": "private, no-store",
            "Last-Modified": row["updated_at"].strftime("%a, %d %b %Y %H:%M:%S GMT"),
        },
    )


@apple_wallet_router.post("/log", status_code=200)
def apple_wallet_log() -> dict[str, str]:
    return {"status": "ok"}


def admin_dashboard_path():
    from pathlib import Path

    return Path(__file__).with_name("admin.html")


def _wallet_authorization_token(authorization: str | None) -> str | None:
    if not authorization or not authorization.startswith("ApplePass "):
        return None
    return authorization.removeprefix("ApplePass ")
