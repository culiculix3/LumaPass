import Foundation

public enum PassValidationError: Error, Equatable, LocalizedError {
    case missingTitle
    case missingOrganization
    case textTooLong(String)
    case barcodeTooLong
    case imageTooLarge
    case invalidColor

    public var errorDescription: String? {
        switch self {
        case .missingTitle: "Añade un nombre para el pase."
        case .missingOrganization: "Añade el nombre visible de la organización."
        case let .textTooLong(field): "\(field) supera el límite de 100 caracteres."
        case .barcodeTooLong: "El código no puede superar los 512 caracteres."
        case .imageTooLarge: "La imagen debe ocupar 4 MB o menos."
        case .invalidColor: "El color debe ser un valor hexadecimal de seis caracteres."
        }
    }
}

public enum PassValidator {
    public static let imageByteLimit = 4 * 1_024 * 1_024
    public static let barcodeCharacterLimit = 512

    public static func validate(_ draft: PassDraft) -> [PassValidationError] {
        var errors: [PassValidationError] = []
        if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.missingTitle)
        }
        if draft.organization.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.missingOrganization)
        }

        let fields = [
            ("El nombre del pase", draft.title),
            ("La organización", draft.organization),
            ("La etiqueta principal", draft.primaryLabel),
            ("El campo principal", draft.primaryValue),
            ("La etiqueta secundaria", draft.secondaryLabel),
            ("El campo secundario", draft.secondaryValue),
            ("La etiqueta adicional", draft.additionalLabel),
            ("El campo adicional", draft.additionalValue)
        ]
        errors += fields.compactMap { name, value in
            value.count > 100 ? .textTooLong(name) : nil
        }

        if draft.barcodeValue.count > barcodeCharacterLimit {
            errors.append(.barcodeTooLong)
        }
        if let imageData = draft.imageData, imageData.count > imageByteLimit {
            errors.append(.imageTooLarge)
        }
        if !isHexColor(draft.backgroundHex) || !isHexColor(draft.foregroundHex) {
            errors.append(.invalidColor)
        }
        return errors
    }

    public static func isHexColor(_ value: String) -> Bool {
        let digits = value.hasPrefix("#") ? value.dropFirst() : value[...]
        return digits.count == 6 && digits.allSatisfy(\.isHexDigit)
    }
}
