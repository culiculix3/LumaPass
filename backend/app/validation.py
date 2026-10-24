import io
import re

from PIL import Image, ImageFile, ImageOps, UnidentifiedImageError

HEX_COLOR = re.compile(r"^#?[0-9A-Fa-f]{6}$")
ALLOWED_IMAGE_FORMATS = {"JPEG", "PNG", "WEBP"}
MAX_IMAGE_DIMENSION = 6_000
MAX_IMAGE_PIXELS = 25_000_000
MAX_TEXT_LENGTH = 100
MAX_BARCODE_LENGTH = 512
Image.MAX_IMAGE_PIXELS = MAX_IMAGE_PIXELS
ImageFile.LOAD_TRUNCATED_IMAGES = False


def safe_text(value: str, *, field_name: str, optional: bool = True) -> str:
    cleaned = " ".join(value.split())
    if not optional and not cleaned:
        raise ValueError(f"{field_name} es obligatorio.")
    if len(cleaned) > MAX_TEXT_LENGTH:
        raise ValueError(f"{field_name} supera el límite de {MAX_TEXT_LENGTH} caracteres.")
    if any(ord(character) < 32 for character in cleaned):
        raise ValueError(f"{field_name} contiene caracteres no permitidos.")
    return cleaned


def parse_hex_color(value: str, *, field_name: str = "color") -> tuple[int, int, int]:
    if not HEX_COLOR.fullmatch(value):
        raise ValueError(f"{field_name} debe ser un valor hexadecimal de seis caracteres.")
    offset = 1 if value.startswith("#") else 0
    return tuple(int(value[index : index + 2], 16) for index in (offset, offset + 2, offset + 4))


def validate_barcode(value: str, format_name: str) -> str:
    if len(value) > MAX_BARCODE_LENGTH:
        raise ValueError("El contenido del código supera los 512 caracteres.")
    if format_name not in {"QR", "Code128"}:
        raise ValueError("El formato del código no está admitido.")
    if format_name == "Code128" and value and not value.isascii():
        raise ValueError("Code 128 solo admite texto ASCII en este formato.")
    if format_name == "QR" and value and not value.encode("utf-8").isascii():
        try:
            value.encode("iso-8859-1")
        except UnicodeEncodeError as error:
            raise ValueError("El código QR contiene caracteres no admitidos.") from error
    return value


def normalize_image(image_bytes: bytes, max_upload_bytes: int) -> tuple[bytes, int, int]:
    if not image_bytes or len(image_bytes) > max_upload_bytes:
        raise ValueError("La imagen debe tener contenido y no superar 5 MB.")
    try:
        with Image.open(io.BytesIO(image_bytes)) as image:
            if image.format not in ALLOWED_IMAGE_FORMATS:
                raise ValueError("Utiliza una imagen JPEG, PNG o WebP.")
            image.verify()
        with Image.open(io.BytesIO(image_bytes)) as image:
            image.load()
            if image.width > MAX_IMAGE_DIMENSION or image.height > MAX_IMAGE_DIMENSION:
                raise ValueError("Cada lado de la imagen debe medir 6000 píxeles o menos.")
            if image.width * image.height > MAX_IMAGE_PIXELS:
                raise ValueError("La resolución de la imagen supera el límite permitido.")
            normalized = ImageOps.exif_transpose(image).convert("RGB")
            normalized.thumbnail((2_400, 2_400), Image.Resampling.LANCZOS)
            output = io.BytesIO()
            normalized.save(
                output,
                format="JPEG",
                quality=88,
                optimize=True,
                progressive=True,
            )
            data = output.getvalue()
    except (UnidentifiedImageError, OSError, Image.DecompressionBombError) as error:
        raise ValueError(
            "El archivo no es una imagen válida o supera el límite de píxeles."
        ) from error

    if len(data) > max_upload_bytes:
        raise ValueError("La imagen procesada supera el límite de almacenamiento.")
    return data, normalized.width, normalized.height


def dominant_colors(image_bytes: bytes) -> list[str]:
    with Image.open(io.BytesIO(image_bytes)) as image:
        palette = image.convert("RGB").quantize(colors=3)
        colors = palette.getcolors(maxcolors=3) or []
        colors.sort(reverse=True)
        palette_colors = palette.getpalette()
        if palette_colors is None:
            return []
        return [
            "#{:02X}{:02X}{:02X}".format(*palette_colors[index * 3 : index * 3 + 3])
            for _, index in colors
        ]
