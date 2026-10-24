import Foundation

public enum GalleryCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    case minimal = "Minimalista"
    case abstract = "Abstracto"
    case neon = "Neón"
    case elegant = "Elegante"
    case retro = "Retro"
    case nature = "Naturaleza"
    case art = "Arte"
    case technology = "Tecnología"

    public var id: String { rawValue }
}

public enum TemplateLicense: String, Codable, CaseIterable, Identifiable, Sendable {
    case cc0 = "CC0 1.0"
    case ccBy = "CC BY 4.0"

    public var id: String { rawValue }
}

public struct GalleryTemplate: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let description: String
    public let creator: String
    public let category: GalleryCategory
    public let tags: [String]
    public let backgroundHex: String
    public let foregroundHex: String
    public let license: TemplateLicense
    public let uses: Int
    public let creatorID: String?

    public init(
        id: String,
        title: String,
        description: String,
        creator: String = "LumaPass Studio",
        category: GalleryCategory,
        tags: [String],
        backgroundHex: String,
        foregroundHex: String = "FFFFFF",
        license: TemplateLicense = .cc0,
        uses: Int,
        creatorID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.creator = creator
        self.category = category
        self.tags = tags
        self.backgroundHex = backgroundHex
        self.foregroundHex = foregroundHex
        self.license = license
        self.uses = uses
        self.creatorID = creatorID
    }

    public static let collection: [GalleryTemplate] = [
        GalleryTemplate(
            id: "aurora", title: "Aurora", description: "Luz suave sobre el horizonte.",
            category: .abstract, tags: ["gradiente", "noche"], backgroundHex: "40356F", uses: 1482
        ),
        GalleryTemplate(
            id: "atelier", title: "Atelier", description: "Un lienzo limpio y contemporáneo.",
            category: .minimal, tags: ["limpio", "diseño"], backgroundHex: "243A38", uses: 1206
        ),
        GalleryTemplate(
            id: "afterglow", title: "Afterglow", description: "Color eléctrico, líneas calmadas.",
            category: .neon, tags: ["neón", "noche"], backgroundHex: "54245F", uses: 982
        ),
        GalleryTemplate(
            id: "monogram", title: "Monograma", description: "Elegancia serena, sin excesos.",
            category: .elegant, tags: ["premium", "editorial"], backgroundHex: "3A332E", uses: 844
        ),
        GalleryTemplate(
            id: "sunroom", title: "Sunroom", description: "Una tarde dorada en calma.",
            category: .nature, tags: ["luz", "cálido"], backgroundHex: "714C31", uses: 729
        ),
        GalleryTemplate(
            id: "signal", title: "Señal", description: "Contraste preciso con energía retro.",
            category: .retro, tags: ["geométrico", "color"], backgroundHex: "254064", uses: 691
        ),
        GalleryTemplate(
            id: "silk", title: "Seda", description: "Una composición suave y sofisticada.",
            category: .art, tags: ["textura", "arte"], backgroundHex: "683B50", uses: 614
        ),
        GalleryTemplate(
            id: "orbit", title: "Órbita", description: "Una paleta cósmica y nítida.",
            category: .technology, tags: ["digital", "espacio"], backgroundHex: "273758", uses: 560
        )
    ]
}
