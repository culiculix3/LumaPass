import LumaPassCore
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct CommunityUploadView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var title = ""
    @State private var description = ""
    @State private var category: GalleryCategory = .abstract
    @State private var license: TemplateLicense = .cc0
    @State private var confirmedRights = false
    @State private var isSubmitting = false
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var showingFileImporter = false

    private var canSubmit: Bool {
        imageData != nil
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && title.count <= 80
            && description.count <= 240
            && confirmedRights
            && appState.isSignedIn
            && !isSubmitting
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    if let imageData, let image = UIImage(data: imageData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 175)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 15))
                            .accessibilityLabel("Vista previa del fondo que se va a compartir")
                    } else {
                        ContentUnavailableView(
                            "Elige un fondo original",
                            systemImage: "photo.on.rectangle.angled",
                            description: Text("La comunidad solo comparte el fondo; tus campos privados del pase nunca se publican.")
                        )
                        .frame(height: 170)
                    }
                    HStack(spacing: 10) {
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Label("Fotos", systemImage: "photo")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(Color.lumaAccent)
                        Button {
                            showingFileImporter = true
                        } label: {
                            Label("Archivos", systemImage: "folder")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(Color.lumaAccent)
                    }
                    .disabled(isImporting)
                }
                .listRowBackground(Color.clear)
            }

            Section("El fondo") {
                TextField("Título", text: $title)
                    .accessibilityLabel("Título del fondo")
                    .onChange(of: title) { _, value in
                        if value.count > 80 { title = String(value.prefix(80)) }
                    }
                Text("\(title.count) de 80 caracteres")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                TextField("Descripción breve", text: $description, axis: .vertical)
                    .lineLimit(2...4)
                    .accessibilityLabel("Descripción del fondo")
                    .onChange(of: description) { _, value in
                        if value.count > 240 { description = String(value.prefix(240)) }
                    }
                Picker("Categoría", selection: $category) {
                    ForEach(GalleryCategory.allCases) { category in
                        Text(category.rawValue).tag(category)
                    }
                }
                Picker("Licencia", selection: $license) {
                    ForEach(TemplateLicense.allCases) { license in
                        Text(license.rawValue).tag(license)
                    }
                }
                .accessibilityHint("La licencia se mostrará en la página de este fondo.")
            }

            Section("Confirmación de derechos") {
                Toggle(isOn: $confirmedRights) {
                    Text("Confirmo que tengo los derechos necesarios y que este fondo no suplanta marcas, bancos, personas ni eventos.")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .tint(Color.lumaAccent)
                ToggleLegalNote()
                if !appState.isSignedIn {
                    AppleSignInButton { token, name, error in
                        if let error {
                            errorMessage = "No se inició sesión con Apple: \(error.localizedDescription)"
                            return
                        }
                        guard let token else {
                            errorMessage = "Apple no devolvió un token de identidad válido."
                            return
                        }
                        appState.identityToken = token
                        appState.accountName = name
                        appState.isSignedIn = true
                    }
                }
            }

            Section {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Button(action: submit) {
                    HStack(spacing: 9) {
                        if isSubmitting { ProgressView() }
                        Text(isSubmitting ? "Enviando a revisión…" : "Enviar a revisión")
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(!canSubmit)
                .accessibilityHint("El fondo se procesa sin metadatos, se almacena de forma privada y requiere revisión antes de publicarse.")
            } footer: {
                Text("La imagen se optimiza en este dispositivo y se envía a un almacenamiento privado para una revisión humana. El fondo no será público hasta que se apruebe.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.lumaCanvas.ignoresSafeArea())
        .navigationTitle("Compartir un fondo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancelar") { dismiss() }
            }
        }
        .onChange(of: selectedPhoto) { _, item in
            Task { await importPhoto(item) }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                guard let url = urls.first else {
                    errorMessage = "No se seleccionó ningún archivo."
                    return
                }
                Task { await importFile(url) }
            case let .failure(error):
                errorMessage = "No se pudo abrir el archivo: \(error.localizedDescription)"
            }
        }
    }

    private func importPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        isImporting = true
        defer { isImporting = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorMessage = "No se pudo leer esta foto. Elige otra imagen."
                return
            }
            imageData = try PassArtworkRenderer.normalizePhoto(data).data
            errorMessage = nil
        } catch {
            errorMessage = "No se pudo procesar la foto: \(error.localizedDescription)"
        }
    }

    private func importFile(_ url: URL) async {
        isImporting = true
        defer { isImporting = false }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            imageData = try PassArtworkRenderer.normalizePhoto(data).data
            errorMessage = nil
        } catch {
            errorMessage = "No se pudo importar ni optimizar el archivo: \(error.localizedDescription)"
        }
    }

    private func submit() {
        guard let identityToken = appState.identityToken, let imageData else {
            errorMessage = "Inicia sesión con Apple y selecciona una imagen antes de continuar."
            return
        }
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                try await WalletAPIClient().uploadCommunityAsset(
                    imageData: imageData,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                    category: category.rawValue,
                    license: license.rawValue,
                    identityToken: identityToken
                )
                appState.notice = AppNotice(
                    message: "El fondo se envió a revisión. Solo se publicará cuando el equipo de moderación lo apruebe.",
                    isError: false
                )
                dismiss()
            } catch {
                errorMessage = "No se pudo enviar el fondo: \(error.localizedDescription)"
            }
        }
    }
}

private struct ToggleLegalNote: View {
    var body: some View {
        Text("No se admiten contenidos ilegales, ofensivos, sexuales explícitos, fraudulentos, con derechos vulnerados ni que imiten tarjetas de pago o servicios de Apple.")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}
