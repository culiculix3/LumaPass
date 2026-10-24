import LumaPassCore
import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState
    let onCreate: () -> Void
    let onExplore: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                hero
                if let draft = appState.designs.first {
                    VStack(alignment: .leading, spacing: 13) {
                        HStack {
                            Text("Continúa donde lo dejaste").font(.headline)
                            Spacer()
                            Text("\(appState.designs.count) diseños")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        PassCardView(draft: draft, showPreviewNotice: true)
                        Text(draft.title.isEmpty ? "Borrador sin título" : draft.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    emptyDesigns
                }
                collectionSection
                footer
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 36)
            .frame(maxWidth: 580)
            .frame(maxWidth: .infinity)
        }
        .background(Color.lumaCanvas.ignoresSafeArea())
        .navigationBarHidden(true)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("LumaPass")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .tracking(-0.8)
                Text("Un pase, hecho a tu manera.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.lumaAccent)
                .frame(width: 46, height: 46)
                .background(Color.lumaAccent.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 9) {
                Text("TU PRÓXIMA IDEA")
                    .font(.caption2.weight(.bold))
                    .tracking(2)
                    .foregroundStyle(Color.lumaAccent)
                Text("Crea algo que\nquieras llevar contigo.")
                    .font(.system(size: 30, weight: .medium, design: .rounded))
                    .tracking(-0.9)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: onCreate) {
                Label("Crear un pase", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.lumaAccent, in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(Color.lumaCanvas)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Elige el tipo y el diseño de tu nuevo pase.")
        }
        .lumaCard()
        .background {
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.25, green: 0.20, blue: 0.39), Color.lumaCanvas],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    private var emptyDesigns: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Tu primera creación")
                    .font(.headline)
                Spacer()
                Image(systemName: "wand.and.stars")
                    .foregroundStyle(Color.lumaAccent)
                    .accessibilityHidden(true)
            }
            Text("Elige una idea, dale tu estilo y guarda un borrador privado. Empezar lleva menos de un minuto.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button(action: onCreate) {
                Label("Empezar a crear", systemImage: "arrow.right")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.lumaAccent)
            .padding(.top, 3)
        }
        .lumaCard()
    }

    private var collectionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Una pequeña colección")
                    .font(.headline)
                Spacer()
                Button("Explorar") { onExplore() }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.lumaAccent)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(GalleryTemplate.collection.prefix(4))) { template in
                        VStack(alignment: .leading, spacing: 8) {
                            TemplateArtView(template: template)
                                .frame(width: 175, height: 106)
                                .clipShape(RoundedRectangle(cornerRadius: 17))
                            Text(template.title).font(.subheadline.weight(.medium))
                            Text(template.category.rawValue)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 175, alignment: .leading)
                    }
                }
            }
            .contentMargins(.trailing, 5)
        }
    }

    private var footer: some View {
        Label("Diseños propios. Pases legítimos. Tu información es tuya.", systemImage: "lock.shield")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 6)
    }
}
