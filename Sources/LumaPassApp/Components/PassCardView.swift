import LumaPassCore
import SwiftUI
import UIKit

struct PassCardView: View {
    let draft: PassDraft
    var showWatchPreview = false
    var showPreviewNotice = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            cardBackground
            VStack(alignment: .leading, spacing: 0) {
                header
                Spacer(minLength: 18)
                VStack(alignment: .leading, spacing: 6) {
                    Text(draft.primaryLabel.isEmpty ? "TU PASE" : draft.primaryLabel.uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(1.7)
                        .foregroundStyle(Color(hex: draft.foregroundHex).opacity(0.72))
                    Text(draft.primaryValue.isEmpty ? (draft.title.isEmpty ? "Un pase a tu manera" : draft.title) : draft.primaryValue)
                        .font(.system(size: 23, weight: .semibold, design: .rounded))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(Color(hex: draft.foregroundHex))
                }
                HStack(alignment: .top, spacing: 16) {
                    previewField(label: draft.secondaryLabel.isEmpty ? "DETALLES" : draft.secondaryLabel, value: draft.secondaryValue)
                    if !draft.additionalLabel.isEmpty || !draft.additionalValue.isEmpty {
                        previewField(label: draft.additionalLabel, value: draft.additionalValue)
                    }
                }
                .padding(.top, 18)
                .padding(.bottom, 17)
                Rectangle().fill(Color(hex: draft.foregroundHex).opacity(0.16)).frame(height: 1)
                HStack(spacing: 8) {
                    Image(systemName: draft.barcodeKind == .qr ? "qrcode" : "barcode")
                        .font(.system(size: 16, weight: .medium))
                        .accessibilityHidden(true)
                    Text(draft.barcodeValue.isEmpty ? "El código se añade al generar" : draft.barcodeValue)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .foregroundStyle(Color(hex: draft.foregroundHex).opacity(0.78))
                .padding(.top, 12)
            }
            .padding(showWatchPreview ? 16 : 21)
        }
        .frame(height: showWatchPreview ? 165 : 248)
        .clipShape(RoundedRectangle(cornerRadius: showWatchPreview ? 37 : 26))
        .overlay {
            RoundedRectangle(cornerRadius: showWatchPreview ? 37 : 26)
                .strokeBorder(Color.lumaSurface.opacity(0.13), lineWidth: 1)
        }
        .shadow(color: Color(hex: draft.backgroundHex).opacity(0.28), radius: 24, y: 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Vista previa ilustrativa: \(draft.kind.title), \(draft.title.isEmpty ? "sin título" : draft.title)")
        .overlay(alignment: .bottomTrailing) {
            if showPreviewNotice {
                Text("VISTA PREVIA")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.25), in: Capsule())
                    .padding(12)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private var cardBackground: some View {
        let cornerRadius: CGFloat = showWatchPreview ? 37 : 26
        if let imageData = draft.imageData, let image = UIImage(data: imageData) {
            GeometryReader { proxy in
                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .scaleEffect(draft.imageScale)
                        .offset(x: draft.imageOffsetX, y: draft.imageOffsetY)
                        .brightness(draft.imageBrightness)
                        .contrast(draft.imageContrast)
                        .blur(radius: draft.imageBlur)
                    LinearGradient(
                        colors: [
                            Color(hex: draft.backgroundHex).opacity(draft.gradientStrength + 0.24),
                            Color(hex: draft.backgroundHex).opacity(draft.gradientStrength)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
        } else {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color(hex: draft.backgroundHex).gradient)
                Circle()
                    .fill(Color.lumaAccent.opacity(0.34))
                    .frame(width: 180, height: 180)
                    .blur(radius: 38)
                    .offset(x: showWatchPreview ? 40 : 190, y: 30)
                    .accessibilityHidden(true)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(draft.organization.isEmpty ? "TU ORGANIZACIÓN" : draft.organization)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .tracking(0.8)
                    .lineLimit(1)
                Text(draft.kind.title.uppercased())
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(Color(hex: draft.foregroundHex).opacity(0.65))
            }
            .foregroundStyle(Color(hex: draft.foregroundHex))
            Spacer()
            Image(systemName: draft.kind.symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color(hex: draft.foregroundHex).opacity(0.86))
                .accessibilityHidden(true)
        }
    }

    private func previewField(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !label.isEmpty {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .tracking(0.9)
                    .foregroundStyle(Color(hex: draft.foregroundHex).opacity(0.62))
                    .lineLimit(1)
            }
            Text(value.isEmpty ? "Añade un campo" : value)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color(hex: draft.foregroundHex))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct TemplateArtView: View {
    let template: GalleryTemplate
    var remoteImageURL: URL? = nil

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [Color(hex: template.backgroundHex), Color(hex: template.backgroundHex).opacity(0.6), Color.lumaAccent.opacity(0.34)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                if let remoteImageURL {
                    AsyncImage(url: remoteImageURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.clear
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                }
                Circle()
                    .fill(Color(hex: template.foregroundHex).opacity(0.18))
                    .frame(width: proxy.size.width * 0.62)
                    .blur(radius: 18)
                    .offset(x: proxy.size.width * 0.29, y: -proxy.size.height * 0.13)
                RoundedRectangle(cornerRadius: 60)
                    .fill(Color.lumaAccent.opacity(0.13))
                    .frame(width: proxy.size.width * 0.55, height: proxy.size.height * 0.52)
                    .rotationEffect(.degrees(-28))
                    .blur(radius: 8)
                    .offset(x: -proxy.size.width * 0.18, y: proxy.size.height * 0.25)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .accessibilityHidden(true)
        }
    }
}
