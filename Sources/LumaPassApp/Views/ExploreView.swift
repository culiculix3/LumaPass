import LumaPassCore
import SwiftUI
import UIKit

struct ExploreView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""
    @State private var selectedCategory: GalleryCategory?
    @State private var collection = ExploreCollection.trending
    @State private var editorDraft: PassDraft?
    @State private var reportedTemplate: GalleryTemplate?
    @State private var creatorToBlock: GalleryTemplate?
    @State private var showingCommunityUpload = false

    private var templates: [GalleryTemplate] {
        var result = GalleryTemplate.collection + appState.communityAssets.map { asset in
            GalleryTemplate(
                id: asset.id,
                title: asset.title,
                description: asset.description,
                creator: "Comunidad",
                category: GalleryCategory(rawValue: asset.category) ?? .abstract,
                tags: asset.tags,
                backgroundHex: asset.dominantColors.first ?? "40356F",
                license: TemplateLicense(rawValue: asset.license) ?? .cc0,
                uses: asset.uses,
                creatorID: asset.creatorId
            )
        }
        if let selectedCategory {
            result = result.filter { $0.category == selectedCategory }
        }
        if !searchText.isEmpty {
            let query = searchText.localizedLowercase
            result = result.filter {
                $0.title.localizedLowercase.contains(query)
                    || $0.description.localizedLowercase.contains(query)
                    || $0.category.rawValue.localizedLowercase.contains(query)
                    || $0.tags.contains { $0.localizedLowercase.contains(query) }
            }
        }
        switch collection {
        case .trending: result.sort { $0.uses > $1.uses }
        case .new: result.reverse()
        case .favorites: result = result.filter { appState.favorites.contains($0.id) }
        }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                searchField
                collectionPicker
                categoryPicker
                if templates.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(templates) { template in
                            templateCard(template)
                        }
                    }
                }
                if WalletAPIClient().isConfigured {
                    Button {
                        showingCommunityUpload = true
                    } label: {
                        Label("Compartir un fondo original", systemImage: "square.and.arrow.up")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Color.lumaAccent.opacity(0.13), in: RoundedRectangle(cornerRadius: 15))
                            .foregroundStyle(Color.lumaAccent)
                    }
                    .buttonStyle(.plain)
                }
                privacyNote
            }
            .padding(20)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background(Color.lumaCanvas.ignoresSafeArea())
        .navigationTitle("Explorar")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if WalletAPIClient().isConfigured {
                await refreshCommunity()
            }
        }
        .refreshable { await refreshCommunity() }
        .sheet(item: $editorDraft) { draft in
            NavigationStack { PassEditorView(initialDraft: draft) }
        }
        .sheet(isPresented: $showingCommunityUpload) {
            NavigationStack { CommunityUploadView() }
        }
        .confirmationDialog(
            "¿Qué problema has encontrado en «\(reportedTemplate?.title ?? "este diseño")»?",
            isPresented: Binding(
                get: { reportedTemplate != nil },
                set: { if !$0 { reportedTemplate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Contenido ilegal", role: .destructive) { submitReport(reason: "illegal") }
            Button("Contenido ofensivo", role: .destructive) { submitReport(reason: "offensive") }
            Button("Uso no autorizado de derechos", role: .destructive) { submitReport(reason: "copyright") }
            Button("Suplantación o fraude", role: .destructive) { submitReport(reason: "fraud") }
            Button("Cancelar", role: .cancel) { reportedTemplate = nil }
        } message: {
            Text("Los fondos y diseños públicos se pueden reportar para que los revise el equipo de moderación.")
        }
        .confirmationDialog(
            "¿Bloquear a \(creatorToBlock?.creator ?? "esta persona")?",
            isPresented: Binding(
                get: { creatorToBlock != nil },
                set: { if !$0 { creatorToBlock = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Bloquear creador", role: .destructive) { blockCreator() }
            Button("Cancelar", role: .cancel) { creatorToBlock = nil }
        } message: {
            Text("Los fondos de esta persona se ocultarán de tu galería cuando navegues con tu cuenta.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Una galería hecha para inspirar.")
                .font(.title2.weight(.medium))
                .tracking(-0.45)
            Text("Fondos originales para tus pases. Los datos personales permanecen privados.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Busca una idea o un color", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit { Task { await refreshCommunity() } }
                .accessibilityLabel("Buscar en la galería")
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .accessibilityLabel("Borrar búsqueda")
            }
        }
        .font(.subheadline)
        .padding(13)
        .background(Color.lumaSurface.opacity(0.06), in: RoundedRectangle(cornerRadius: 15))
    }

    private var collectionPicker: some View {
        HStack(spacing: 6) {
            ForEach(ExploreCollection.allCases) { value in
                Button {
                    collection = value
                } label: {
                    Text(value.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(collection == value ? Color.lumaCanvas : .secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background {
                            if collection == value { Capsule().fill(Color.lumaAccent) }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(collection == value ? .isSelected : [])
            }
        }
        .padding(5)
        .background(Color.lumaSurface.opacity(0.05), in: Capsule())
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip(nil)
                ForEach(GalleryCategory.allCases) { category in
                    categoryChip(category)
                }
            }
        }
        .contentMargins(.trailing, 3)
    }

    private func categoryChip(_ category: GalleryCategory?) -> some View {
        let title = category?.rawValue ?? "Todo"
        return Button {
            selectedCategory = category
        } label: {
            Text(title)
                .font(.caption)
                .foregroundStyle(selectedCategory == category ? Color.lumaAccent : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Color.lumaSurface.opacity(selectedCategory == category ? 0.09 : 0.035),
                    in: Capsule()
                )
                .overlay(Capsule().strokeBorder(Color.lumaSurface.opacity(0.06), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedCategory == category ? .isSelected : [])
    }

    private func templateCard(_ template: GalleryTemplate) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .topTrailing) {
                TemplateArtView(template: template, remoteImageURL: remoteImageURL(for: template))
                    .overlay(alignment: .bottomLeading) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 23, weight: .light))
                            .foregroundStyle(.white.opacity(0.84))
                            .padding(13)
                            .accessibilityHidden(true)
                    }
                Button {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.72)) {
                        appState.toggleFavorite(template)
                    }
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    if template.creatorID != nil {
                        Task { await syncFavorite(template) }
                    }
                } label: {
                    Image(systemName: appState.favorites.contains(template.id) ? "heart.fill" : "heart")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(appState.favorites.contains(template.id) ? Color.pink : Color.white)
                        .frame(width: 34, height: 34)
                        .background(.black.opacity(0.28), in: Circle())
                }
                .padding(9)
                .accessibilityLabel(appState.favorites.contains(template.id) ? "Quitar de guardados" : "Guardar en favoritos")
                .accessibilityAddTraits(appState.favorites.contains(template.id) ? .isSelected : [])
            }
            .frame(height: 112)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(template.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Menu {
                        Button("Reportar contenido", systemImage: "flag") {
                            reportedTemplate = template
                        }
                        if template.creatorID != nil {
                            Button("Bloquear creador", systemImage: "person.crop.circle.badge.minus", role: .destructive) {
                                creatorToBlock = template
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Más opciones para \(template.title)")
                }
                Text(template.category.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text(template.creator)
                    Spacer()
                    Text("\(template.uses.formatted()) usos")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal")
                    Text(template.license.rawValue)
                    Spacer()
                    Text(template.tags.prefix(2).joined(separator: " · "))
                        .lineLimit(1)
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
                Button {
                    Task { await applyTemplate(template) }
                } label: {
                    Text("Aplicar diseño")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color.lumaAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: 11))
                        .foregroundStyle(Color.lumaAccent)
                }
                .buttonStyle(.plain)
                .padding(.top, 3)
            }
            .padding(.horizontal, 3)
        }
        .padding(9)
        .background(Color.lumaSurface.opacity(0.035), in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Color.lumaSurface.opacity(0.055), lineWidth: 1)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            collection == .favorites ? "Aún no has guardado diseños" : "No encontramos resultados",
            systemImage: collection == .favorites ? "heart" : "sparkle.magnifyingglass",
            description: Text(collection == .favorites
                ? "Toca el corazón de una plantilla para tenerla a mano."
                : "Prueba otro término o categoría.")
        )
        .padding(.top, 26)
    }

    private var privacyNote: some View {
        Label(
            "Esta selección incluye plantillas originales de demostración; no se comparten datos del pase.",
            systemImage: "lock.shield"
        )
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 5)
    }

    private func submitReport(reason: String) {
        guard let reportedTemplate else { return }
        guard let assetID = reportedTemplate.creatorID else {
            appState.notice = AppNotice(
                message: "La plantilla «\(reportedTemplate.title)» forma parte de la colección editorial de demostración y no es contenido comunitario denunciable.",
                isError: true
            )
            self.reportedTemplate = nil
            return
        }
        guard let token = appState.identityToken else {
            appState.notice = AppNotice(message: "Inicia sesión con Apple antes de enviar un reporte.", isError: true)
            self.reportedTemplate = nil
            return
        }
        Task {
            do {
                try await WalletAPIClient().reportCommunityAsset(
                    id: assetID,
                    reason: reason,
                    identityToken: token
                )
                appState.notice = AppNotice(message: "Reporte enviado para revisión por una persona moderadora.", isError: false)
            } catch {
                appState.notice = AppNotice(message: "No se pudo enviar el reporte: \(error.localizedDescription)", isError: true)
            }
        }
        self.reportedTemplate = nil
    }

    private func remoteImageURL(for template: GalleryTemplate) -> URL? {
        appState.communityAssets.first { $0.id == template.id }?.imageURL
    }

    private func refreshCommunity() async {
        guard WalletAPIClient().isConfigured else { return }
        do {
            appState.communityAssets = try await WalletAPIClient().loadCommunityAssets(
                query: searchText,
                category: selectedCategory?.rawValue,
                order: collection == .new ? "new" : "trending",
                identityToken: appState.identityToken
            )
        } catch {
            appState.notice = AppNotice(message: "No se pudo actualizar la galería de la comunidad: \(error.localizedDescription)", isError: true)
        }
    }

    private func syncFavorite(_ template: GalleryTemplate) async {
        guard let token = appState.identityToken else {
            appState.notice = AppNotice(
                message: "El favorito se guardó en este dispositivo. Inicia sesión para sincronizarlo con tu cuenta.",
                isError: false
            )
            return
        }
        do {
            try await WalletAPIClient().favoriteCommunityAsset(
                id: template.id,
                isFavorite: appState.favorites.contains(template.id),
                identityToken: token
            )
        } catch {
            appState.notice = AppNotice(message: "No se pudo sincronizar el favorito: \(error.localizedDescription)", isError: true)
        }
    }

    private func blockCreator() {
        guard let creatorToBlock, let token = appState.identityToken else {
            appState.notice = AppNotice(message: "Inicia sesión con Apple para bloquear a una persona.", isError: true)
            self.creatorToBlock = nil
            return
        }
        Task {
            do {
                try await WalletAPIClient().blockCommunityCreator(
                    assetID: creatorToBlock.id,
                    identityToken: token
                )
                if let creatorID = creatorToBlock.creatorID {
                    appState.communityAssets.removeAll { $0.creatorId == creatorID }
                }
                appState.notice = AppNotice(message: "La persona se ha bloqueado. Sus fondos ya no aparecen en tu galería.", isError: false)
            } catch {
                appState.notice = AppNotice(message: "No se pudo bloquear esta cuenta: \(error.localizedDescription)", isError: true)
            }
        }
        self.creatorToBlock = nil
    }

    private func applyTemplate(_ template: GalleryTemplate) async {
        var draft = PassDraft.starter(kind: .generic, template: template)
        guard let url = remoteImageURL(for: template) else {
            editorDraft = draft
            return
        }
        do {
            let image = try await WalletAPIClient().downloadCommunityImage(from: url)
            draft.imageData = try PassArtworkRenderer.normalizePhoto(image).data
            if let token = appState.identityToken {
                try await WalletAPIClient().recordCommunityAssetUse(id: template.id, identityToken: token)
            }
            editorDraft = draft
        } catch {
            appState.notice = AppNotice(message: "No se pudo aplicar este fondo: \(error.localizedDescription)", isError: true)
        }
    }
}

private enum ExploreCollection: String, CaseIterable, Identifiable {
    case trending
    case new
    case favorites

    var id: String { rawValue }
    var title: String {
        switch self {
        case .trending: "Tendencias"
        case .new: "Nuevos"
        case .favorites: "Guardados"
        }
    }
}
