import XCTest
@testable import LumaPassCore

final class PassValidatorTests: XCTestCase {
    func testEmptyDraftReportsBothRequiredFields() {
        let errors = PassValidator.validate(PassDraft())

        XCTAssertTrue(errors.contains(.missingTitle))
        XCTAssertTrue(errors.contains(.missingOrganization))
    }

    func testCompleteDraftPassesValidation() {
        let draft = PassDraft(
            title: "Club del barrio",
            organization: "Café de muestra",
            primaryLabel: "SOCIA",
            primaryValue: "Ana",
            barcodeValue: "lumapass-demo-123"
        )

        XCTAssertTrue(PassValidator.validate(draft).isEmpty)
    }

    func testRejectsOversizedBarcodeAndInvalidColors() {
        var draft = PassDraft(
            title: "Entrada",
            organization: "Sala de muestra",
            barcodeValue: String(repeating: "a", count: 513)
        )
        draft.backgroundHex = "bank-card"

        let errors = PassValidator.validate(draft)
        XCTAssertTrue(errors.contains(.barcodeTooLong))
        XCTAssertTrue(errors.contains(.invalidColor))
    }

    func testAcceptsHexColorWithOptionalHash() {
        XCTAssertTrue(PassValidator.isHexColor("#A1b2C3"))
        XCTAssertTrue(PassValidator.isHexColor("3D3475"))
        XCTAssertFalse(PassValidator.isHexColor("#12345"))
    }
}
