import Foundation

public enum PassKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case generic
    case membership
    case loyalty
    case coupon
    case ticket

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .generic: "Pase general"
        case .membership: "Membresía"
        case .loyalty: "Fidelización"
        case .coupon: "Cupón"
        case .ticket: "Entrada"
        }
    }

    public var symbol: String {
        switch self {
        case .generic: "rectangle.on.rectangle"
        case .membership: "person.text.rectangle"
        case .loyalty: "star.circle"
        case .coupon: "tag"
        case .ticket: "ticket"
        }
    }
}

public enum BarcodeKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case qr
    case code128

    public var id: String { rawValue }
    public var title: String { self == .qr ? "QR" : "Code 128" }
}

public struct PassDraft: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var kind: PassKind
    public var title: String
    public var organization: String
    public var primaryLabel: String
    public var primaryValue: String
    public var secondaryLabel: String
    public var secondaryValue: String
    public var additionalLabel: String
    public var additionalValue: String
    public var barcodeValue: String
    public var barcodeKind: BarcodeKind
    public var expiresAt: Date?
    public var backgroundHex: String
    public var foregroundHex: String
    public var templateID: String
    public var imageData: Data?
    public var imageBrightness: Double
    public var imageContrast: Double
    public var imageBlur: Double
    public var gradientStrength: Double
    public var imageScale: Double
    public var imageOffsetX: Double
    public var imageOffsetY: Double
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        kind: PassKind = .generic,
        title: String = "",
        organization: String = "",
        primaryLabel: String = "",
        primaryValue: String = "",
        secondaryLabel: String = "",
        secondaryValue: String = "",
        additionalLabel: String = "",
        additionalValue: String = "",
        barcodeValue: String = "",
        barcodeKind: BarcodeKind = .qr,
        expiresAt: Date? = nil,
        backgroundHex: String = "3D3475",
        foregroundHex: String = "FFFFFF",
        templateID: String = "aurora",
        imageData: Data? = nil,
        imageBrightness: Double = 0,
        imageContrast: Double = 1,
        imageBlur: Double = 0,
        gradientStrength: Double = 0.36,
        imageScale: Double = 1,
        imageOffsetX: Double = 0,
        imageOffsetY: Double = 0,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.organization = organization
        self.primaryLabel = primaryLabel
        self.primaryValue = primaryValue
        self.secondaryLabel = secondaryLabel
        self.secondaryValue = secondaryValue
        self.additionalLabel = additionalLabel
        self.additionalValue = additionalValue
        self.barcodeValue = barcodeValue
        self.barcodeKind = barcodeKind
        self.expiresAt = expiresAt
        self.backgroundHex = backgroundHex
        self.foregroundHex = foregroundHex
        self.templateID = templateID
        self.imageData = imageData
        self.imageBrightness = imageBrightness
        self.imageContrast = imageContrast
        self.imageBlur = imageBlur
        self.gradientStrength = gradientStrength
        self.imageScale = imageScale
        self.imageOffsetX = imageOffsetX
        self.imageOffsetY = imageOffsetY
        self.updatedAt = updatedAt
    }

    public static func starter(kind: PassKind, template: GalleryTemplate) -> PassDraft {
        PassDraft(
            kind: kind,
            title: "",
            organization: "",
            primaryLabel: kind == .coupon ? "DESCUENTO" : "TITULAR",
            secondaryLabel: kind == .ticket ? "FECHA" : "CATEGORÍA",
            additionalLabel: "NÚMERO",
            backgroundHex: template.backgroundHex,
            foregroundHex: template.foregroundHex,
            templateID: template.id
        )
    }
}
