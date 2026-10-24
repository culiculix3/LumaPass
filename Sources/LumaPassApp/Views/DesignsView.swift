import LumaPassCore
import SwiftUI

struct DesignsView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedDraft: PassDraft?
    @State private var showingDeleteConfirmation = false
    @State private var draftToDelete: PassDraft?

    var body: some View {
        Group {
            if appState.designs.isEmpty {
                ContentUnavailableView {
                    Label("Aquí empieza tu colección", systemImage: "rectangle.stack")
                } description: {
                    Text("Los borradores se guardan en este dispositivo, de forma privada.")
                } actions: {
                    Button("Crear un pase") {
                        selectedDraft = .starter(kind: .generic, template: GalleryTemplate.collection[0])
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.lumaAccent)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(appState.designs) { draft in
                            VStack(alignment: .leading, spacing: 10) {
                                Button {
                                    selectedDraft = draft
                                } label: {
                                    VStack(alignment: .leading, spacing: 10) {
                                        PassCardView(draft: draft, showPreviewNotice: true)
                                        HStack {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(draft.title.isEmpty ? "Borrador sin título" : draft.title)
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundStyle(.primary)
                                                Text("\(draft.kind.title) · \(draft.updatedAt, style: .relative)")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Image(systemName: "pencil")
                                                .font(.caption.weight(.medium))
                                                .foregroundStyle(Color.lumaAccent)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Abre este borrador para editarlo.")
                            }
                            .padding(12)
                            .background(Color.lumaSurface.opacity(0.035), in: RoundedRectangle(cornerRadius: 22))
                            .contextMenu {
                                Button("Editar", systemImage: "pencil") { selectedDraft = draft }
                                Button("Eliminar", systemImage: "trash", role: .destructive) {
                                    draftToDelete = draft
                                    showingDeleteConfirmation = true
                                }
                            }
                            .swipeActions {
                                Button("Eliminar", systemImage: "trash", role: .destructive) {
                                    appState.delete(draft)
                                }
                            }
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: 600)
                    .frame(maxWidth: .infinity)
                }
                .background(Color.lumaCanvas.ignoresSafeArea())
            }
        }
        .navigationTitle("Mis diseños")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedDraft) { draft in
            NavigationStack { PassEditorView(initialDraft: draft) }
        }
        .confirmationDialog(
            "¿Eliminar este borrador?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Eliminar borrador", role: .destructive) {
                if let draftToDelete { appState.delete(draftToDelete) }
                draftToDelete = nil
            }
            Button("Conservar", role: .cancel) { draftToDelete = nil }
        } message: {
            Text("No es posible deshacer esta acción.")
        }
    }
}
