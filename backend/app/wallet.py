import hashlib
import json
import re
import secrets
import subprocess  # nosec B404 -- used only to invoke fixed OpenSSL arguments without a shell.
import tempfile
import uuid
import zipfile
from datetime import UTC, datetime
from io import BytesIO
from pathlib import Path
from typing import Any

from fastapi import HTTPException
from PIL import Image, ImageDraw, ImageOps

from .settings import Settings, settings
from .validation import parse_hex_color, safe_text, validate_barcode

PASS_KINDS = {"generic", "membership", "loyalty", "coupon", "ticket"}
BARCODES = {
    "QR": "PKBarcodeFormatQR",
    "Code128": "PKBarcodeFormatCode128",
}
PASS_STYLES = {
    "generic": "generic",
    "membership": "storeCard",
    "loyalty": "storeCard",
    "coupon": "coupon",
    "ticket": "eventTicket",
}


def safe_filename_identifier(value: str) -> bool:
    return bool(re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9-]{0,63}", value))


def build_pass_document(
    content: dict[str, Any],
    *,
    serial_number: str,
    authentication_token: str,
    updated_at: datetime | None = None,
    configuration: Settings = settings,
) -> dict[str, Any]:
    if not configuration.pass_type_identifier or not configuration.apple_team_identifier:
        raise ValueError("La configuración de Pass Type ID de Apple está incompleta.")
    kind = content.get("type")
    if kind not in PASS_STYLES:
        raise ValueError("El tipo de pase no está permitido.")

    title = safe_text(content.get("title", ""), field_name="El nombre del pase", optional=False)
    organization = safe_text(
        content.get("organization", ""),
        field_name="La organización",
        optional=False,
    )
    background = parse_hex_color(content.get("backgroundHex", ""), field_name="El fondo")
    foreground = parse_hex_color(content.get("foregroundHex", ""), field_name="El texto")

    primary_label = safe_text(content.get("primaryLabel", ""), field_name="La etiqueta principal")
    primary_value = safe_text(content.get("primaryValue", ""), field_name="El campo principal")
    secondary_label = safe_text(
        content.get("secondaryLabel", ""), field_name="La etiqueta secundaria"
    )
    secondary_value = safe_text(content.get("secondaryValue", ""), field_name="El campo secundario")
    additional_label = safe_text(
        content.get("additionalLabel", ""), field_name="La etiqueta adicional"
    )
    additional_value = safe_text(
        content.get("additionalValue", ""), field_name="El campo adicional"
    )

    barcode_value = content.get("barcodeValue", "")
    barcode_kind = content.get("barcodeKind", "QR")
    validate_barcode(barcode_value, barcode_kind)

    rgb_background = "rgb({}, {}, {})".format(*background)
    rgb_foreground = "rgb({}, {}, {})".format(*foreground)
    primary_fields = [
        {"key": "title", "label": primary_label or "PASE", "value": primary_value or title},
    ]
    footer_fields = []
    fallback_secondary = []
    fallback_auxiliary = []
    if secondary_label or secondary_value:
        field = {"key": "detail", "label": secondary_label or "DETALLES", "value": secondary_value}
        footer_fields.append(field)
        fallback_secondary.append(field)
    if additional_label or additional_value:
        field = {"key": "number", "label": additional_label or "NÚMERO", "value": additional_value}
        footer_fields.append(field)
        fallback_auxiliary.append(field)

    back_fields = [
        {
            "key": "pass-information",
            "label": "INFORMACIÓN DEL PASE",
            "value": f"Pase digital de {organization}. No es una tarjeta de pago.",
        }
    ]
    expiration = content.get("expiresAt")
    if expiration:
        expiration = datetime.fromisoformat(expiration)
        if expiration.tzinfo is None:
            expiration = datetime.combine(expiration.date(), expiration.time(), tzinfo=UTC)
        back_fields.append(
            {
                "key": "expiration",
                "label": "VENCIMIENTO",
                "value": expiration.astimezone(UTC).isoformat(),
                "dateStyle": "PKDateStyleMedium",
            }
        )

    pass_document: dict[str, Any] = {
        "formatVersion": 1,
        "passTypeIdentifier": configuration.pass_type_identifier,
        "serialNumber": serial_number,
        "teamIdentifier": configuration.apple_team_identifier,
        "organizationName": organization,
        "description": title,
        "logoText": organization,
        "foregroundColor": rgb_foreground,
        "labelColor": rgb_foreground,
        "backgroundColor": rgb_background,
        "sharingProhibited": True,
        "userInfo": {},
        "posterGeneric": {
            "headerFields": [
                {"key": "organization", "label": "ORGANIZACIÓN", "value": organization}
            ],
            "primaryFields": primary_fields,
            "footerFields": footer_fields[:2],
            "backFields": back_fields,
        },
        PASS_STYLES[kind]: {
            "headerFields": [
                {"key": "organization", "label": "ORGANIZACIÓN", "value": organization}
            ],
            "primaryFields": primary_fields,
            "secondaryFields": fallback_secondary[:4],
            "auxiliaryFields": fallback_auxiliary[:4],
            "backFields": back_fields,
        },
    }
    if configuration.public_base_url:
        pass_document["webServiceURL"] = f"{configuration.public_base_url.rstrip('/')}/apple-wallet"
        pass_document["authenticationToken"] = authentication_token
    if barcode_value:
        barcode = {
            "format": BARCODES[barcode_kind],
            "message": barcode_value,
            "messageEncoding": "iso-8859-1",
        }
        pass_document["barcodes"] = [barcode]
    if expiration:
        pass_document["expirationDate"] = expiration.astimezone(UTC).isoformat()
    if content.get("revoked"):
        pass_document["voided"] = True
    return pass_document


def _draw_original_icon(size: int) -> bytes:
    image = Image.new("RGBA", (size, size), (61, 52, 117, 255))
    draw = ImageDraw.Draw(image)
    margin = size // 7
    draw.rounded_rectangle(
        (margin, margin, size - margin, size - margin),
        radius=size // 5,
        outline=(207, 193, 255, 255),
        width=max(2, size // 28),
    )
    draw.arc(
        (size // 4, size // 4, size * 3 // 4, size * 3 // 4),
        215,
        510,
        fill=(255, 255, 255, 255),
        width=max(3, size // 12),
    )
    return _png_bytes(image)


def _draw_original_logo(scale: int) -> bytes:
    image = Image.new("RGBA", (160 * scale, 50 * scale), (0, 0, 0, 0))
    with Image.open(BytesIO(_draw_original_icon(46 * scale))) as mark:
        image.alpha_composite(mark, (2 * scale, 2 * scale))
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle(
        (57 * scale, 15 * scale, 151 * scale, 20 * scale),
        radius=2 * scale,
        fill=(247, 243, 255, 236),
    )
    draw.rounded_rectangle(
        (57 * scale, 28 * scale, 115 * scale, 32 * scale),
        radius=2 * scale,
        fill=(199, 189, 225, 205),
    )
    return _png_bytes(image)


def _png_bytes(image: Image.Image) -> bytes:
    image = image.convert("RGBA")
    output = BytesIO()
    image.save(output, format="PNG", optimize=True)
    return output.getvalue()


def _original_background(content: dict[str, Any]) -> Image.Image:
    width, height = 1_080, 390
    background = parse_hex_color(content.get("backgroundHex", "40356F"))
    image = Image.new("RGB", (width, height))
    draw = ImageDraw.Draw(image, "RGBA")
    for x in range(width):
        blend = x / max(1, width - 1)
        color = tuple(round(channel * (1 - blend) + 24 * blend) for channel in background)
        draw.line((x, 0, x, height), fill=(*color, 255))
    draw.ellipse(
        (width * 0.55, -height * 0.62, width * 1.05, height * 0.85), fill=(218, 200, 255, 38)
    )
    draw.ellipse(
        (-width * 0.18, height * 0.38, width * 0.45, height * 1.6), fill=(105, 194, 174, 29)
    )
    return image


def _pass_images(content: dict[str, Any]) -> dict[str, bytes]:
    files = {
        "icon.png": _draw_original_icon(29),
        "icon@2x.png": _draw_original_icon(58),
        "icon@3x.png": _draw_original_icon(87),
        "logo.png": _draw_original_logo(1),
        "logo@2x.png": _draw_original_logo(2),
        "logo@3x.png": _draw_original_logo(3),
    }
    if content.get("image"):
        import base64
        import binascii

        try:
            image_bytes = base64.b64decode(content["image"], validate=True)
        except (ValueError, binascii.Error) as error:
            raise ValueError("La imagen del pase no es una codificación válida.") from error
        from .validation import normalize_image

        normalized, _, _ = normalize_image(image_bytes, settings.max_upload_bytes)
        with Image.open(BytesIO(normalized)) as source:
            source.thumbnail((1_080, 390), Image.Resampling.LANCZOS)
            art = source.copy()
    else:
        art = _original_background(content)
    if art.size != (1_080, 390):
        canvas = _original_background(content)
        art.thumbnail(canvas.size, Image.Resampling.LANCZOS)
        offset = ((canvas.width - art.width) // 2, (canvas.height - art.height) // 2)
        canvas.paste(art, offset)
        art = canvas
    strip = ImageOps.fit(art, (375, 123), Image.Resampling.LANCZOS)
    files["strip.png"] = _png_bytes(strip)
    files["strip@2x.png"] = _png_bytes(strip.resize((750, 246), Image.Resampling.LANCZOS))
    files["strip@3x.png"] = _png_bytes(strip.resize((1_125, 369), Image.Resampling.LANCZOS))
    if content.get("type") == "generic":
        thumbnail = ImageOps.fit(art, (90, 90), Image.Resampling.LANCZOS)
        files["thumbnail.png"] = _png_bytes(thumbnail)
        files["thumbnail@2x.png"] = _png_bytes(
            thumbnail.resize((180, 180), Image.Resampling.LANCZOS)
        )
        files["thumbnail@3x.png"] = _png_bytes(
            thumbnail.resize((270, 270), Image.Resampling.LANCZOS)
        )
    return files


def _sign_manifest(manifest_path: Path, output_path: Path) -> None:
    command = [
        "openssl",
        "smime",
        "-binary",
        "-sign",
        "-certfile",
        settings.apple_wwdr_certificate_path,
        "-signer",
        settings.pass_certificate_path,
        "-inkey",
        settings.pass_private_key_path,
        "-in",
        str(manifest_path),
        "-out",
        str(output_path),
        "-outform",
        "DER",
        "-md",
        "sha1",
    ]
    if settings.pass_private_key_passphrase:
        command.extend(["-passin", "stdin"])
    try:
        completed = subprocess.run(  # nosec B603 -- fixed argv; user content is not an argument.
            command,
            check=False,
            capture_output=True,
            timeout=30,
            shell=False,
            input=(
                settings.pass_private_key_passphrase.encode("utf-8")
                if settings.pass_private_key_passphrase
                else None
            ),
        )
    except subprocess.TimeoutExpired as error:
        raise HTTPException(
            status_code=503, detail="La firma del pase ha agotado el tiempo."
        ) from error
    except OSError as error:
        raise HTTPException(
            status_code=503, detail="OpenSSL no está disponible en el servidor."
        ) from error
    if completed.returncode:
        raise HTTPException(
            status_code=503,
            detail=(
                "Apple Wallet no aceptó la configuración de firma. "
                "Revisa la cadena de certificados y la clave."
            ),
        )


def create_pkpass(
    content: dict[str, Any],
    *,
    serial_number: str,
    authentication_token: str,
    updated_at: datetime | None = None,
) -> bytes:
    if not settings.wallet_signing_ready():
        raise HTTPException(
            status_code=503,
            detail=(
                "Modo demo: no se ha emitido un pase. Configura en el servidor "
                "un Pass Type ID de Apple válido y sus certificados."
            ),
        )
    if not safe_filename_identifier(serial_number):
        raise HTTPException(status_code=400, detail="El identificador del pase no es válido.")
    try:
        document = build_pass_document(
            content,
            serial_number=serial_number,
            authentication_token=authentication_token,
            updated_at=updated_at,
        )
        pass_images = _pass_images(content)
    except ValueError as error:
        raise HTTPException(status_code=422, detail=str(error)) from error

    with tempfile.TemporaryDirectory(prefix="lumapass-") as temporary:
        root = Path(temporary)
        for name, value in pass_images.items():
            (root / name).write_bytes(value)
        pass_path = root / "pass.json"
        pass_path.write_text(
            json.dumps(document, ensure_ascii=False, separators=(",", ":")),
            encoding="utf-8",
        )
        manifest = {
            path.name: hashlib.sha1(path.read_bytes(), usedforsecurity=False).hexdigest()
            for path in sorted(root.iterdir(), key=lambda item: item.name)
            if path.is_file() and path.name != "manifest.json"
        }
        manifest_path = root / "manifest.json"
        manifest_path.write_text(json.dumps(manifest, separators=(",", ":")), encoding="utf-8")
        signature_path = root / "signature"
        _sign_manifest(manifest_path, signature_path)
        archive = BytesIO()
        with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as package:
            for path in sorted(root.iterdir(), key=lambda item: item.name):
                if path.is_file():
                    package.write(path, arcname=path.name)
        return archive.getvalue()


def new_pass_identity() -> tuple[str, str]:
    return uuid.uuid4().hex, secrets.token_urlsafe(32)
