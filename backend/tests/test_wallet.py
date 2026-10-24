import unittest
from dataclasses import replace
from io import BytesIO

from app.settings import settings
from app.wallet import _pass_images, build_pass_document, create_pkpass
from fastapi import HTTPException
from PIL import Image


class WalletDocumentTests(unittest.TestCase):
    def setUp(self) -> None:
        self.configuration = replace(
            settings,
            pass_type_identifier="pass.app.lumapass",
            apple_team_identifier="TEAM123456",
            public_base_url="https://passes.example.test",
        )
        self.content = {
            "type": "generic",
            "title": "Club Aurora",
            "organization": "Estudio Aurora",
            "primaryLabel": "TITULAR",
            "primaryValue": "Ana",
            "secondaryLabel": "CATEGORÍA",
            "secondaryValue": "Nivel dos",
            "additionalLabel": "NÚMERO",
            "additionalValue": "A-102",
            "barcodeValue": "lumapass-demo-123",
            "barcodeKind": "QR",
            "backgroundHex": "40356F",
            "foregroundHex": "FFFFFF",
        }

    def test_new_poster_style_has_legacy_generic_fallback(self) -> None:
        document = build_pass_document(
            self.content,
            serial_number="test-123",
            authentication_token="sample-token-never-used",
            configuration=self.configuration,
        )

        self.assertIn("posterGeneric", document)
        self.assertIn("generic", document)
        self.assertEqual(document["generic"]["primaryFields"][0]["value"], "Ana")
        self.assertEqual(document["posterGeneric"]["primaryFields"][0]["value"], "Ana")
        self.assertEqual(document["posterGeneric"]["footerFields"][0]["value"], "Nivel dos")
        self.assertEqual(document["barcodes"][0]["format"], "PKBarcodeFormatQR")
        self.assertTrue(document["sharingProhibited"])
        self.assertEqual(document["webServiceURL"], "https://passes.example.test/apple-wallet")

    def test_each_supported_legacy_style_is_preserved(self) -> None:
        for kind, style in (
            ("membership", "storeCard"),
            ("loyalty", "storeCard"),
            ("coupon", "coupon"),
            ("ticket", "eventTicket"),
        ):
            with self.subTest(kind=kind):
                content = {**self.content, "type": kind}
                document = build_pass_document(
                    content,
                    serial_number="test-123",
                    authentication_token="sample-token-never-used",
                    configuration=self.configuration,
                )
                self.assertIn("posterGeneric", document)
                self.assertIn(style, document)

    def test_naive_expiration_is_interpreted_as_utc(self) -> None:
        content = {**self.content, "expiresAt": "2031-06-15T12:00:00"}
        document = build_pass_document(
            content,
            serial_number="test-expiration",
            authentication_token="sample-token-never-used",
            configuration=self.configuration,
        )

        self.assertEqual(document["expirationDate"], "2031-06-15T12:00:00+00:00")
        self.assertEqual(
            document["posterGeneric"]["backFields"][1]["value"], "2031-06-15T12:00:00+00:00"
        )

    def test_official_barcode_collection_uses_an_array(self) -> None:
        document = build_pass_document(
            self.content,
            serial_number="test-barcode",
            authentication_token="sample-token-never-used",
            configuration=self.configuration,
        )

        self.assertEqual(document["barcodes"][0]["format"], "PKBarcodeFormatQR")

    def test_pass_images_include_correctly_sized_wallet_resources(self) -> None:
        images = _pass_images(self.content)
        expected_sizes = {
            "icon.png": (29, 29),
            "icon@2x.png": (58, 58),
            "icon@3x.png": (87, 87),
            "logo.png": (160, 50),
            "logo@2x.png": (320, 100),
            "logo@3x.png": (480, 150),
            "strip.png": (375, 123),
            "strip@2x.png": (750, 246),
            "strip@3x.png": (1_125, 369),
            "thumbnail.png": (90, 90),
            "thumbnail@2x.png": (180, 180),
            "thumbnail@3x.png": (270, 270),
        }

        for name, size in expected_sizes.items():
            with self.subTest(image=name), Image.open(BytesIO(images[name])) as image:
                self.assertEqual(image.format, "PNG")
                self.assertEqual(image.size, size)

    def test_event_ticket_has_no_conflicting_thumbnail_or_background_image(self) -> None:
        images = _pass_images({**self.content, "type": "ticket"})

        self.assertNotIn("thumbnail.png", images)
        self.assertNotIn("background.png", images)
        self.assertIn("strip.png", images)

    def test_demo_server_never_returns_an_unsigned_pass(self) -> None:
        with self.assertRaises(HTTPException) as error:
            create_pkpass(
                self.content,
                serial_number="test-123",
                authentication_token="sample-token-never-used",
            )
        self.assertEqual(error.exception.status_code, 503)
        self.assertIn("Modo demo", error.exception.detail)


if __name__ == "__main__":
    unittest.main()
