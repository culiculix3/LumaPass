import Foundation
import LumaPassCore
import Observation

@MainActor
@Observable
final class AppState {
    private(set) var designs: [PassDraft] = []
    var favorites: Set<String> = []
    var searchText = ""
    var selectedCategory: GalleryCategory?
    var isSignedIn = false
    var identityToken: String?
    var accountName: String?
    var communityAssets: [CommunityAssetResponse] = []
    var useLightAppearance = false
    var notice: AppNotice?

    private var draftsURL: URL? {
        do {
            let directory = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let storageDirectory = directory.appending(path: "LumaPass", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(
                at: storageDirectory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
            return storageDirectory.appending(path: "private-drafts-v1.json")
        } catch {
            notice = AppNotice(message: "No se pudo preparar el almacenamiento protegido: \(error.localizedDescription)", isError: true)
            return nil
        }
    }

    init() {
        if let draftsURL, FileManager.default.fileExists(atPath: draftsURL.path) {
            do {
                let data = try Data(contentsOf: draftsURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                designs = try decoder.decode([PassDraft].self, from: data)
            } catch {
                notice = AppNotice(message: "No se pudieron leer los borradores protegidos: \(error.localizedDescription)", isError: true)
            }
        }
        favorites = Set(UserDefaults.standard.stringArray(forKey: "lumapass.favorites.v1") ?? [])
        useLightAppearance = UserDefaults.standard.bool(forKey: "lumapass.light.v1")
    }

    func save(_ draft: PassDraft) {
        var updated = draft
        updated.updatedAt = .now
        designs.removeAll { $0.id == updated.id }
        designs.insert(updated, at: 0)
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(designs)
            try data.write(to: draftsURL ?? privateDraftURL(), options: [.atomic, .completeFileProtection])
        } catch {
            notice = AppNotice(message: "No se pudo guardar este diseño: \(error.localizedDescription)", isError: true)
        }
    }

    func delete(_ draft: PassDraft) {
        designs.removeAll { $0.id == draft.id }
        persistDesigns()
    }

    func toggleFavorite(_ template: GalleryTemplate) {
        if favorites.contains(template.id) {
            favorites.remove(template.id)
        } else {
            favorites.insert(template.id)
        }
        UserDefaults.standard.set(Array(favorites), forKey: "lumapass.favorites.v1")
    }

    func setAppearance(light: Bool) {
        useLightAppearance = light
        UserDefaults.standard.set(light, forKey: "lumapass.light.v1")
    }

    func clearAccount() {
        designs.removeAll()
        favorites.removeAll()
        identityToken = nil
        isSignedIn = false
        accountName = nil
        persistDesigns()
        UserDefaults.standard.removeObject(forKey: "lumapass.favorites.v1")
    }

    func persistDesigns() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(designs).write(
                to: draftsURL ?? privateDraftURL(),
                options: [.atomic, .completeFileProtection]
            )
        } catch {
            notice = AppNotice(message: "No se pudo actualizar el almacenamiento local: \(error.localizedDescription)", isError: true)
        }
    }

    private func privateDraftURL() throws -> URL {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let storageDirectory = directory.appending(path: "LumaPass", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: storageDirectory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        return storageDirectory.appending(path: "private-drafts-v1.json")
    }
}

struct AppNotice: Identifiable {
    let id = UUID()
    let message: String
    let isError: Bool
}
