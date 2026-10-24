import SwiftUI

struct ProfileView: View {
    @Environment(AppState.self) private var appState
    @State private var presentedDocument: LegalDocument?
    @State private var confirmDeleteAccount = false
    @State private var confirmSignOut = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: appState.isSignedIn ? "person.crop.circle.fill" : "sparkles")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(Color.lumaAccent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(appState.isSignedIn ? (appState.accountName ?? "Cuenta Apple") : "Tu espacio privado")
                            .font(.headline)
                        Text(appState.isSignedIn ? "Conectado con Sign in with Apple" : "Diseños guardados en este dispositivo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 7)
                if !appState.isSignedIn {
                    AppleSignInButton { token, name, error in
                        if let error {
                            appState.notice = AppNotice(message: "No se inició sesión: \(error.localizedDescription)", isError: true)
                            return
                        }
                        guard let token else {
                            appState.notice = AppNotice(message: "No se recibió un token de identidad de Apple.", isError: true)
                            return
                        }
                        appState.identityToken = token
                        appState.accountName = name
                        appState.isSignedIn = true
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 9, leading: 0, bottom: 3, trailing: 0))
                }
            } header: {
                sectionLabel("CUENTA")
            }

            Section {
                Toggle(isOn: Binding(
                    get: { appState.useLightAppearance },
                    set: { appState.setAppearance(light: $0) }
                )) {
                    Label("Apariencia clara", systemImage: "sun.max")
                }
                .tint(Color.lumaAccent)
            } header: {
                sectionLabel("PREFERENCIAS")
            }

            Section {
                documentButton("Privacidad", symbol: "hand.raised", document: .privacy)
                documentButton("Condiciones de uso", symbol: "doc.text", document: .terms)
                documentButton("Licencias y créditos", symbol: "checkmark.seal", document: .licenses)
                documentButton("Límites de la app", symbol: "info.circle", document: .limits)
            } header: {
                sectionLabel("INFORMACIÓN")
            }

            if appState.isSignedIn {
                Section {
                    Button("Cerrar sesión", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                        confirmSignOut = true
                    }
                    Button("Eliminar la cuenta", systemImage: "person.crop.circle.badge.minus", role: .destructive) {
                        confirmDeleteAccount = true
                    }
                } header: {
                    sectionLabel("TU CUENTA")
                } footer: {
                    Text("Al eliminar la cuenta, el servicio solicitará el borrado de tus datos. Los borradores guardados localmente también se eliminarán.")
                }
            }

            Section {
                Label("Sin datos bancarios. Sin Apple Pay. Sin suplantación de marcas.", systemImage: "checkmark.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 5)
            } header: {
                sectionLabel("NUESTRO COMPROMISO")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.lumaCanvas.ignoresSafeArea())
        .navigationTitle("Perfil")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $presentedDocument) { document in
            NavigationStack {
                ScrollView {
                    Text(document.body)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(22)
                }
                .background(Color.lumaCanvas.ignoresSafeArea())
                .navigationTitle(document.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Cerrar") { presentedDocument = nil }
                    }
                }
            }
        }
        .confirmationDialog(
            "¿Cerrar sesión?",
            isPresented: $confirmSignOut,
            titleVisibility: .visible
        ) {
            Button("Cerrar sesión", role: .destructive) {
                appState.isSignedIn = false
                appState.identityToken = nil
                appState.accountName = nil
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Tus borradores locales se conservarán en este dispositivo.")
        }
        .confirmationDialog(
            "¿Eliminar tu cuenta y todos tus borradores?",
            isPresented: $confirmDeleteAccount,
            titleVisibility: .visible
        ) {
            Button("Eliminar cuenta y datos", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Esta acción no se puede deshacer. Se solicitará al servidor la retirada de tus pases y datos asociados.")
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .tracking(1.4)
            .foregroundStyle(Color.lumaAccent)
    }

    private func documentButton(_ title: String, symbol: String, document: LegalDocument) -> some View {
        Button {
            presentedDocument = document
        } label: {
            Label(title, systemImage: symbol)
                .foregroundStyle(.primary)
        }
    }

    @MainActor
    private func deleteAccount() async {
        guard let token = appState.identityToken else {
            appState.notice = AppNotice(message: "Vuelve a iniciar sesión con Apple para verificar tu cuenta antes de borrarla.", isError: true)
            return
        }
        do {
            let walletNotifications = try await WalletAPIClient().deleteAccount(identityToken: token)
            appState.clearAccount()
            appState.communityAssets.removeAll()
            appState.notice = AppNotice(
                message: "La cuenta y sus datos se han eliminado. \(walletNotifications)",
                isError: walletNotifications.contains("no se han") || walletNotifications.contains("no se enviaron")
            )
        } catch {
            appState.notice = AppNotice(message: "No se pudo eliminar la cuenta: \(error.localizedDescription)", isError: true)
        }
    }
}

private enum LegalDocument: String, Identifiable {
    case privacy, terms, licenses, limits

    var id: String { rawValue }
    var title: String {
        switch self {
        case .privacy: "Privacidad"
        case .terms: "Condiciones de uso"
        case .licenses: "Licencias y créditos"
        case .limits: "Límites de la app"
        }
    }

    var body: String {
        switch self {
        case .privacy:
            """
            LumaPass guarda tus borradores de forma privada en este dispositivo y no comparte el contenido de tus pases con la galería. Solo la emisión de un pase o las acciones que elijas enviar requieren la API configurada.

            No solicitamos, almacenamos ni procesamos números de tarjetas, credenciales bancarias ni credenciales de Apple Wallet. Sign in with Apple verifica tu identidad en el servidor; LumaPass no guarda tu contraseña ni almacena el token de identidad en el dispositivo de forma persistente.

            El servidor de producción debe procesar las imágenes sin metadatos EXIF, usar almacenamiento privado con URLs de caducidad corta, restringir registros y facilitar la descarga y el borrado de datos, conforme al RGPD y a la legislación aplicable.

            Esta versión local mantiene los borradores únicamente en el dispositivo. Al borrar un borrador, se elimina de la lista guardada. Antes de desplegar el servicio, publica una política completa con la identidad y el contacto del responsable, las categorías de datos, la base legal, los encargados, el plazo de conservación y las opciones de derechos RGPD. Esta descripción no reemplaza asesoramiento jurídico.
            """
        case .terms:
            """
            Utiliza LumaPass solo para crear pases legítimos, no financieros, para los que tengas autorización. La app no ofrece ni representa Apple Pay, tarjetas bancarias, tarjetas de crédito o débito, credenciales de acceso, entradas de terceros ni pases emitidos por otras organizaciones.

            Al compartir una plantilla, debes poseer los derechos necesarios, elegir una licencia válida y respetar las marcas, la privacidad y los derechos de terceros. Se prohíbe el material ilegal, ofensivo, sexual explícito, fraudulento, discriminatorio, infractor o que suplante marcas, entidades financieras, eventos u organizaciones.

            Podemos ocultar contenido denunciado o infractor, suspender cuentas y eliminar contenido cuando lo exija la ley o una reclamación de derechos. Para solicitar la retirada por copyright, contacta con el responsable del servicio; la versión demostrativa no recibe denuncias en servidores.
            """
        case .licenses:
            """
            LumaPass se distribuye bajo la licencia Apache-2.0.

            Los fondos originales incluidos en la colección de demostración son gradientes y composiciones abstractas creados en el propio proyecto, sin imágenes ni logotipos de terceros.

            Las plantillas comunitarias deben declarar una licencia CC0 1.0 o CC BY 4.0. El autor conserva la titularidad y garantiza los derechos necesarios. No se incluyen activos de marca de Apple ni se pretende imitar su identidad visual.
            """
        case .limits:
            """
            LumaPass crea y administra pases genéricos, membresías, fidelización, cupones y entradas legítimas. No crea tarjetas de pago ni altera o imita pases de Apple Wallet emitidos por terceros.

            Solo un servidor de confianza con credenciales válidas de Apple Pass Type ID puede firmar un archivo .pkpass para producción. Estos certificados y claves privadas no se incluyen en la app ni en este repositorio. El proyecto no puede añadir pases sin una respuesta firmada y el flujo oficial de PassKit.

            La tarjeta de la app es una vista previa orientativa: Apple Wallet puede variar el diseño según la versión de iOS, el tipo de pase, el dispositivo y la región.
            """
        }
    }
}
