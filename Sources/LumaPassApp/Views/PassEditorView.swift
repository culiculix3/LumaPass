import LumaPassCore
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct PassEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft: PassDraft
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedSection = 0
    @State private var isProcessingImage = false
    @State private var imageWarnings: [String] = []
    @State private var showExpiry = false
    @State private var showSignIn = false
    @State private var isIssuing = false
    @State private var isSyncingDraft = false
    @State private var passData: Data?
    @State private var showingWallet = false
    @State private var showingFileImporter = false

    init(initialDraft: PassDraft) {
        _draft = State(initialValue: initialDraft)
        _showExpiry = State(initialValue: initialDraft.expiresAt != nil)
    }

    private func syncPrivateDraft() {
        guard let token = appState.identityToken else {
            appState.notice = AppNotice(message: "Inicia sesión con Apple antes de sincronizar un borrador.", isError: true)
            return
        }
        let errors = PassValidator.validate(draft)
        guard errors.isEmpty else {
            appState.notice = AppNotice(message: errors.map(\.localizedDescription).joined(separator: "\n"), isError: true)
            return
        }
        isSyncingDraft = true
        Task {
            defer { isSyncingDraft = false }
            do {
                let result = try await WalletAPIClient().syncPrivateDraft(draft, identityToken: token)
                appState.save(draft)
                appState.notice = AppNotice(
                    message: "Borrador sincronizado. Pases Wallet actualizados: \(result.updatedPasses). \(result.walletNotifications)",
                    isError: false
                )
            } catch {
                appState.notice = AppNotice(message: "No se pudo sincronizar el borrador: \(error.localizedDescription)", isError: true)
            }
        }
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    PassCardView(draft: draft, showPreviewNotice: true)
                        .overlay {
                            RoundedRectangle(cornerRadius: 26)
                                .strokeBorder(
                                    Color.lumaAccent.opacity(0.42),
                                    style: StrokeStyle(lineWidth: 1, dash: [6, 5])
                                )
                                .padding(14)
                                .accessibilityHidden(true)
                        }
                    previewNotice
                    watchPreview
                    sectionPicker
                    Group {
                        switch selectedSection {
                        case 0: identityFields
                        case 1: designFields
                        default: barcodeFields
                        }
                    }
                    .id(selectedSection)
                    Button(action: saveDraft) {
                        Label("Guardar borrador privado", systemImage: "square.and.arrow.down")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Color.lumaSurface.opacity(0.085), in: RoundedRectangle(cornerRadius: 17))
                    }
                    .buttonStyle(.plain)
                            if appState.isSignedIn, WalletAPIClient().isConfigured {
                                Button(action: syncPrivateDraft) {
                                    HStack(spacing: 8) {
                                        if isSyncingDraft { ProgressView().tint(Color.lumaAccent) }
                                        Label(
                                            isSyncingDraft ? "Guardando de forma privada…" : "Sincronizar borrador privado",
                                            systemImage: "lock.shield"
                                        )
                                        .font(.subheadline.weight(.medium))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .foregroundStyle(Color.lumaAccent)
                                }
                                .buttonStyle(.plain)
                                .disabled(isSyncingDraft)
                                .accessibilityHint("Guarda el borrador en tu espacio privado y actualiza los pases vinculados.")
                            }
                            walletAction
                    Text("Los datos del pase son tuyos. LumaPass nunca solicita ni almacena datos bancarios.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            .background(Color.lumaCanvas.ignoresSafeArea())
            .safeAreaInset(edge: .top, spacing: 0) {
                if !PassValidator.validate(draft).isEmpty {
                    missingFieldsNotice
                }
            }
            .onChange(of: selectedSection) {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    scrollProxy.scrollTo(selectedSection, anchor: .top)
                }
            }
        }
        .navigationTitle("Personaliza")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Cerrar") { dismiss() }
                    .foregroundStyle(Color.lumaAccent)
            }
        }
        .onChange(of: selectedPhoto) { _, newValue in
            Task { await importPhoto(newValue) }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                guard let url = urls.first else {
                    imageWarnings = ["No se seleccionó ningún archivo."]
                    return
                }
                Task { await importImageFile(url) }
            case let .failure(error):
                imageWarnings = ["No se pudo abrir el archivo: \(error.localizedDescription)"]
            }
        }
        .sheet(isPresented: $showingWallet, onDismiss: { passData = nil }) {
            if let passData {
                WalletAddPassView(
                    passData: passData,
                    onCompletion: { _, didAdd in
                        showingWallet = false
                        appState.notice = AppNotice(
                            message: didAdd
                                ? "El pase se añadió correctamente mediante el flujo oficial de Apple Wallet."
                                : "El pase no se añadió a Apple Wallet.",
                            isError: !didAdd
                        )
                        if didAdd { dismiss() }
                    },
                    onFailure: { message in
                        showingWallet = false
                        appState.notice = AppNotice(message: message, isError: true)
                    }
                )
            }
        }
    }

    private var previewNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                "En iOS y watchOS 27 o posterior, LumaPass prioriza el diseño Poster Generic.",
                systemImage: "sparkles.rectangle.stack"
            )
            Label(
                "Incluye un pase genérico compatible con versiones anteriores. La vista es orientativa.",
                systemImage: "info.circle"
            )
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var watchPreview: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("También en Apple Watch")
                .font(.subheadline.weight(.semibold))
            PassCardView(draft: draft, showWatchPreview: true, showPreviewNotice: true)
                .frame(width: 190, height: 165)
                .frame(maxWidth: .infinity, alignment: .center)
            Text("Vista aproximada: Apple decide qué campos y arte muestra según el tipo de pase.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color.lumaSurface.opacity(0.035), in: RoundedRectangle(cornerRadius: 20))
    }

    private var sectionPicker: some View {
        HStack(spacing: 6) {
            sectionButton("Detalles", index: 0)
            sectionButton("Diseño", index: 1)
            sectionButton("Código", index: 2)
        }
        .padding(5)
        .background(Color.lumaSurface.opacity(0.055), in: Capsule())
        .accessibilityLabel("Secciones del editor")
    }

    private func sectionButton(_ title: String, index: Int) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            selectedSection = index
        } label: {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(selectedSection == index ? Color.lumaCanvas : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background {
                    if selectedSection == index {
                        Capsule().fill(Color.lumaAccent)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedSection == index ? .isSelected : [])
    }

    private var missingFieldsNotice: some View {
        let errors = PassValidator.validate(draft)
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(errors.prefix(3).enumerated()), id: \.offset) { _, error in
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .accessibilityElement(children: .combine)
    }

    private var identityFields: some View {
        VStack(alignment: .leading, spacing: 15) {
            sectionHeading("La información de tu pase", subtitle: "Los campos son nativos de Apple Wallet; no se hornean en las imágenes.")
            textField("Nombre del pase", text: $draft.title, placeholder: "p. ej., Club Aurora")
            textField("Nombre visible", text: $draft.organization, placeholder: "p. ej., Estudio Aurora")
            Divider().overlay(Color.lumaSurface.opacity(0.1))
            textField("Etiqueta principal", text: $draft.primaryLabel, placeholder: "TITULAR")
            textField("Campo principal", text: $draft.primaryValue, placeholder: "Tu nombre o número")
            textField("Etiqueta secundaria", text: $draft.secondaryLabel, placeholder: "CATEGORÍA")
            textField("Campo secundario", text: $draft.secondaryValue, placeholder: "Tu nivel o sector")
            textField("Etiqueta adicional", text: $draft.additionalLabel, placeholder: "NÚMERO")
            textField("Campo adicional", text: $draft.additionalValue, placeholder: "Dato opcional")
            Toggle("Añadir fecha de vencimiento", isOn: $showExpiry)
                .tint(Color.lumaAccent)
                .onChange(of: showExpiry) { _, enabled in
                    draft.expiresAt = enabled ? (draft.expiresAt ?? .now.addingTimeInterval(86_400 * 30)) : nil
                }
            if showExpiry {
                DatePicker(
                    "Vence",
                    selection: Binding(
                        get: { draft.expiresAt ?? .now.addingTimeInterval(86_400 * 30) },
                        set: { draft.expiresAt = $0 }
                    ),
                    in: Date.now...Date.distantFuture,
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
            }
            VStack(alignment: .leading, spacing: 8) {
                Label("Mantén el contenido claro y respetuoso.", systemImage: "checkmark.shield")
                Label("No crees pases de pago, marcas falsas ni entradas fraudulentas.", systemImage: "exclamationmark.shield")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
        }
        .lumaCard()
    }

    private var designFields: some View {
        VStack(alignment: .leading, spacing: 17) {
            sectionHeading("Arte, color y contraste", subtitle: "Ajusta una imagen propia; los elementos esenciales del pase siguen siendo campos nativos.")
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label(isProcessingImage ? "Procesando imagen…" : "Elegir una imagen de Fotos", systemImage: "photo.on.rectangle.angled")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.lumaAccent.opacity(0.15), in: RoundedRectangle(cornerRadius: 15))
            }
            .disabled(isProcessingImage)
            .tint(Color.lumaAccent)
            .accessibilityHint("Las fotos se normalizan y limitan a cuatro megabytes.")
            Button {
                showingFileImporter = true
            } label: {
                Label("Elegir una imagen de Archivos", systemImage: "folder")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.lumaSurface.opacity(0.07), in: RoundedRectangle(cornerRadius: 15))
            }
            .buttonStyle(.plain)
            .disabled(isProcessingImage)
            imageQualityWarnings
            Text("Colores")
                .font(.subheadline.weight(.semibold))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
                ForEach(["40356F", "243A38", "54245F", "3A332E", "714C31", "254064", "683B50", "273758"], id: \.self) { hex in
                    Button {
                        draft.backgroundHex = hex
                        draft.foregroundHex = "FFFFFF"
                    } label: {
                        Circle()
                            .fill(Color(hex: hex).gradient)
                            .frame(height: 42)
                            .overlay {
                                if draft.backgroundHex == hex {
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                }
                            }
                            .overlay(Circle().strokeBorder(Color.lumaSurface.opacity(0.18), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Seleccionar color \(hex)")
                    .accessibilityAddTraits(draft.backgroundHex == hex ? .isSelected : [])
                }
            }
            contrastIndicator
            Text("Imagen")
                .font(.subheadline.weight(.semibold))
            sliderControl("Brillo", value: $draft.imageBrightness, range: -0.4...0.4, symbol: "sun.max")
            sliderControl("Contraste", value: $draft.imageContrast, range: 0.7...1.4, symbol: "circle.lefthalf.filled")
            sliderControl("Desenfoque", value: $draft.imageBlur, range: 0...12, symbol: "drop.halffull")
            sliderControl("Gradiente", value: $draft.gradientStrength, range: 0.1...0.85, symbol: "circle.bottomhalf.filled")
            sliderControl("Zoom", value: $draft.imageScale, range: 1...2, symbol: "plus.magnifyingglass")
            sliderControl("Posición horizontal", value: $draft.imageOffsetX, range: -60...60, symbol: "arrow.left.and.right")
            sliderControl("Posición vertical", value: $draft.imageOffsetY, range: -60...60, symbol: "arrow.up.and.down")
            if UIImage(data: draft.imageData ?? Data()) != nil {
                Button(role: .destructive) {
                    draft.imageData = nil
                    imageWarnings = []
                } label: {
                    Label("Quitar imagen", systemImage: "trash")
                }
                .font(.caption.weight(.medium))
            }
            Group {
                Text("Zona segura aproximada")
                    .font(.subheadline.weight(.semibold))
                Text("Mantén texto, logotipos y elementos importantes en la vista previa, dentro del recuadro punteado. El sistema de Apple puede recortar o disponer el arte de forma diferente.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .lumaCard()
    }

    private var imageQualityWarnings: some View {
        Group {
            ForEach(imageWarnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var contrastIndicator: some View {
        let contrast = contrastRatio(foreground: draft.foregroundHex, background: draft.backgroundHex)
        return Label(
            contrast >= 4.5 ? "Contraste \(contrast, specifier: "%.1f"):1, legible" : "Contraste bajo: elige una combinación más clara",
            systemImage: contrast >= 4.5 ? "checkmark.circle" : "exclamationmark.triangle"
        )
        .font(.caption.weight(.medium))
        .foregroundStyle(contrast >= 4.5 ? Color.green : Color.orange)
        .accessibilityLabel(contrast >= 4.5 ? "Buen contraste de texto" : "Advertencia: contraste de texto bajo")
    }

    private var barcodeFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeading("Código del pase", subtitle: "Introduce únicamente un dato que tengas derecho a usar. No uses números bancarios.")
            Picker("Formato de código", selection: $draft.barcodeKind) {
                ForEach(BarcodeKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            textField("Contenido del código", text: $draft.barcodeValue, placeholder: "Un enlace o identificador propio")
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Text("\(draft.barcodeValue.count) de \(PassValidator.barcodeCharacterLimit) caracteres")
                .font(.caption2)
                .foregroundStyle(draft.barcodeValue.count > PassValidator.barcodeCharacterLimit ? .orange : .secondary)
            HStack(spacing: 8) {
                Image(systemName: draft.barcodeKind == .qr ? "qrcode" : "barcode")
                    .font(.title3)
                    .foregroundStyle(Color.lumaAccent)
                Text("Código \(draft.barcodeKind.title)")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(draft.barcodeValue.isEmpty ? "Muestra" : "Vista previa")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(13)
            .background(Color.lumaSurface.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
            Label("La previsualización del código no se puede escanear.", systemImage: "info.circle")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .lumaCard()
    }

    @ViewBuilder
    private var walletAction: some View {
        if appState.isSignedIn {
            Button(action: issuePass) {
                HStack {
                    if isIssuing { ProgressView().tint(Color.lumaCanvas) }
                    Label(isIssuing ? "Generando de forma segura…" : "Añadir a Apple Wallet", systemImage: "wallet.pass")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.lumaAccent, in: RoundedRectangle(cornerRadius: 17))
                .foregroundStyle(Color.lumaCanvas)
            }
            .buttonStyle(.plain)
            .disabled(isIssuing || !PassValidator.validate(draft).isEmpty)
            .accessibilityHint("Solicita un pase firmado y presenta el diálogo oficial de Apple Wallet.")
        } else {
            VStack(spacing: 12) {
                AppleSignInButton { token, name, error in
                    handleSignIn(token: token, name: name, error: error)
                }
                Text("Con Sign in with Apple, la API verifica tu identidad antes de emitir un pase.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if showSignIn, !PassValidator.validate(draft).isEmpty {
                    Text("Completa el nombre del pase y de la organización antes de emitir.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func textField(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .padding(12)
                .background(Color.lumaSurface.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel(title)
        }
    }

    private func sectionHeading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 3)
    }

    private func sliderControl(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        symbol: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.medium))
            Slider(value: value, in: range)
                .tint(Color.lumaAccent)
                .accessibilityLabel(title)
        }
    }

    private func importPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        isProcessingImage = true
        defer { isProcessingImage = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                imageWarnings = ["No se pudo leer la imagen seleccionada. Elige otra foto."]
                return
            }
            imageWarnings = []
            let photo = try PassArtworkRenderer.normalizePhoto(data)
            if min(photo.width, photo.height) < 600 {
                imageWarnings.append("La imagen tiene baja resolución y puede perder nitidez.")
            }
            draft.imageData = photo.data
        } catch {
            imageWarnings = ["No se pudo importar la foto: \(error.localizedDescription)"]
        }
    }

    private func importImageFile(_ url: URL) async {
        isProcessingImage = true
        defer { isProcessingImage = false }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let photo = try PassArtworkRenderer.normalizePhoto(data)
            draft.imageData = photo.data
            imageWarnings = min(photo.width, photo.height) < 600
                ? ["La imagen tiene baja resolución y puede perder nitidez."]
                : []
        } catch {
            imageWarnings = ["No se pudo importar ni optimizar el archivo: \(error.localizedDescription)"]
        }
    }

    private func saveDraft() {
        appState.save(draft)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        dismiss()
    }

    private func handleSignIn(token: String?, name: String?, error: Error?) {
        if let error {
            appState.notice = AppNotice(message: "No se inició sesión con Apple: \(error.localizedDescription)", isError: true)
            return
        }
        guard let token else {
            appState.notice = AppNotice(message: "No se recibió un token de identidad de Apple.", isError: true)
            return
        }
        appState.identityToken = token
        appState.isSignedIn = true
        appState.accountName = name
        showSignIn = false
    }

    private func issuePass() {
        let errors = PassValidator.validate(draft)
        guard errors.isEmpty else {
            appState.notice = AppNotice(message: errors.map(\.localizedDescription).joined(separator: "\n"), isError: true)
            return
        }
        guard appState.identityToken != nil else {
            appState.isSignedIn = false
            showSignIn = true
            return
        }
        isIssuing = true
        Task {
            defer { isIssuing = false }
            do {
                let data = try await WalletAPIClient().issue(draft, identityToken: appState.identityToken)
                passData = data
                showingWallet = true
            } catch {
                appState.notice = AppNotice(message: error.localizedDescription, isError: true)
            }
        }
    }

    private func contrastRatio(foreground: String, background: String) -> Double {
        func luminance(_ hex: String) -> Double {
            let value = UInt64(hex.hasPrefix("#") ? String(hex.dropFirst()) : hex, radix: 16) ?? 0
            let components = [16, 8, 0].map { Double((value >> $0) & 0xFF) / 255 }
            let linear = components.map { color in
                color <= 0.04045 ? color / 12.92 : pow((color + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
        }
        let values = [luminance(foreground), luminance(background)].sorted(by: >)
        return (values[0] + 0.05) / (values[1] + 0.05)
    }
}
