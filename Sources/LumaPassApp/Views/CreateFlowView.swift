import LumaPassCore
import SwiftUI
import UIKit

struct CreateFlowView: View {
    @State private var selectedKind: PassKind = .generic
    @State private var selectedTemplate = GalleryTemplate.collection[0]
    @State private var editorDraft: PassDraft?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 27) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Una buena idea empieza con una forma.")
                        .font(.title2.weight(.medium))
                    Text("Elige el tipo de pase; siempre podrás cambiar los detalles.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("01", "Elige el tipo")
                    ForEach(PassKind.allCases) { kind in
                        kindRow(kind)
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("02", "Encuentra tu estilo")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 13) {
                        ForEach(GalleryTemplate.collection) { template in
                            templateButton(template)
                        }
                    }
                }
                Button {
                    editorDraft = .starter(kind: selectedKind, template: selectedTemplate)
                } label: {
                    Label("Personalizar mi pase", systemImage: "arrow.right")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.lumaAccent, in: RoundedRectangle(cornerRadius: 17))
                        .foregroundStyle(Color.lumaCanvas)
                }
                .buttonStyle(.plain)
            }
            .padding(22)
            .frame(maxWidth: 580)
            .frame(maxWidth: .infinity)
        }
        .background(Color.lumaCanvas.ignoresSafeArea())
        .navigationTitle("Crear")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editorDraft) { draft in
            NavigationStack {
                PassEditorView(initialDraft: draft)
            }
        }
    }

    private func sectionTitle(_ number: String, _ title: String) -> some View {
        HStack(spacing: 9) {
            Text(number)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.lumaAccent)
            Text(title)
                .font(.headline)
        }
        .padding(.bottom, 3)
    }

    private func kindRow(_ kind: PassKind) -> some View {
        let isSelected = selectedKind == kind
        return Button {
            withAnimation(.snappy(duration: 0.2)) { selectedKind = kind }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(spacing: 13) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isSelected ? Color.lumaAccent : .secondary)
                    .frame(width: 39, height: 39)
                    .background(Color.lumaSurface.opacity(0.065), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text(kind.title).font(.subheadline.weight(.semibold))
                    Text(description(for: kind))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.lumaAccent : .tertiary)
            }
            .padding(13)
            .background(Color.lumaSurface.opacity(isSelected ? 0.09 : 0.035), in: RoundedRectangle(cornerRadius: 19))
            .overlay {
                RoundedRectangle(cornerRadius: 19)
                    .strokeBorder(
                        isSelected ? Color.lumaAccent.opacity(0.62) : Color.lumaSurface.opacity(0.06),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func description(for kind: PassKind) -> String {
        switch kind {
        case .generic: "Un pase para tus propias ideas."
        case .membership: "Una membresía personal y elegante."
        case .loyalty: "Una tarjeta para un programa de fidelidad."
        case .coupon: "Una oferta o un descuento legítimo."
        case .ticket: "Una entrada de un evento."
        }
    }

    private func templateButton(_ template: GalleryTemplate) -> some View {
        let isSelected = selectedTemplate.id == template.id
        return Button {
            withAnimation(.snappy(duration: 0.2)) { selectedTemplate = template }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                TemplateArtView(template: template)
                    .frame(height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                HStack {
                    Text(template.title).font(.caption.weight(.semibold))
                    Spacer(minLength: 2)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.lumaAccent)
                    }
                }
                .foregroundStyle(.primary)
            }
            .padding(9)
            .background(Color.lumaSurface.opacity(isSelected ? 0.08 : 0.035), in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(
                        isSelected ? Color.lumaAccent.opacity(0.62) : Color.lumaSurface.opacity(0.06),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
