import io
import unittest

from app.validation import (
    dominant_colors,
    normalize_image,
    parse_hex_color,
    safe_text,
    validate_barcode,
)
from PIL import Image


def jpeg_with_exif() -> bytes:
    image = Image.new("RGB", (640, 480), (45, 72, 98))
    exif = Image.Exif()
    exif[0x010F] = "Private camera model"
    output = io.BytesIO()
    image.save(output, "JPEG", exif=exif)
    return output.getvalue()


def sideways_jpeg_with_orientation() -> bytes:
    image = Image.new("RGB", (80, 40), (45, 72, 98))
    exif = Image.Exif()
    exif[0x0112] = 6
    output = io.BytesIO()
    image.save(output, "JPEG", exif=exif)
    return output.getvalue()


class ValidationTests(unittest.TestCase):
    def test_rejects_missing_required_text_and_long_values(self) -> None:
        with self.assertRaisesRegex(ValueError, "obligatorio"):
            safe_text("  ", field_name="El título", optional=False)
        with self.assertRaisesRegex(ValueError, "100 caracteres"):
            safe_text("x" * 101, field_name="La etiqueta")

    def test_colors_require_six_hex_digits(self) -> None:
        self.assertEqual(parse_hex_color("#3d3475"), (61, 52, 117))
        self.assertEqual(parse_hex_color("3d3475"), (61, 52, 117))
        with self.assertRaisesRegex(ValueError, "hexadecimal"):
            parse_hex_color("bank-color")

    def test_barcode_formats_and_limits_are_checked(self) -> None:
        self.assertEqual(validate_barcode("club-demo-123", "Code128"), "club-demo-123")
        with self.assertRaisesRegex(ValueError, "512"):
            validate_barcode("x" * 513, "QR")
        with self.assertRaisesRegex(ValueError, "ASCII"):
            validate_barcode("entrée", "Code128")

    def test_photo_normalization_removes_exif_metadata(self) -> None:
        original = jpeg_with_exif()
        normalized, width, height = normalize_image(original, 2 * 1024 * 1024)

        self.assertEqual((width, height), (640, 480))
        self.assertNotIn(b"Private camera model", normalized)
        with Image.open(io.BytesIO(normalized)) as image:
            self.assertEqual(image.getexif(), {})
            self.assertEqual(image.format, "JPEG")

    def test_image_orientation_is_preserved_without_retaining_exif(self) -> None:
        normalized, width, height = normalize_image(
            sideways_jpeg_with_orientation(), 2 * 1024 * 1024
        )

        self.assertEqual((width, height), (40, 80))
        with Image.open(io.BytesIO(normalized)) as image:
            self.assertEqual(image.getexif(), {})

    def test_rejects_large_and_non_image_uploads(self) -> None:
        with self.assertRaisesRegex(ValueError, "no superar"):
            normalize_image(b"x" * 128, 64)
        with self.assertRaisesRegex(ValueError, "imagen válida"):
            normalize_image(b"not an image", 1024)

    def test_extracted_dominant_colors_are_hex_values(self) -> None:
        normalized, _, _ = normalize_image(jpeg_with_exif(), 2 * 1024 * 1024)

        colors = dominant_colors(normalized)
        self.assertTrue(colors)
        self.assertLessEqual(len(colors), 3)
        self.assertTrue(all(len(color) == 7 and color.startswith("#") for color in colors))


if __name__ == "__main__":
    unittest.main()
