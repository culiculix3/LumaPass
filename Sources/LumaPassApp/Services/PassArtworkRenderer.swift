import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import LumaPassCore
import UIKit

enum PassArtworkError: LocalizedError {
    case unsupportedImage
    case sourceTooLarge
    case lowMemory
    case outputTooLarge

    var errorDescription: String? {
        switch self {
        case .unsupportedImage: "La imagen no se pudo leer. Prueba con JPEG, PNG o HEIC."
        case .sourceTooLarge: "La imagen supera el límite seguro de 30 MB."
        case .lowMemory: "La imagen tiene demasiados píxeles para procesarla de forma segura."
        case .outputTooLarge: "La imagen optimizada supera los 4 MB permitidos."
        }
    }
}

struct NormalizedPhoto {
    let data: Data
    let width: Int
    let height: Int
}

enum PassArtworkRenderer {
    private static let inputByteLimit = 30 * 1_024 * 1_024
    private static let pixelLimit = 30_000_000

    static func normalizePhoto(_ data: Data, maximumBytes: Int = PassValidator.imageByteLimit) throws -> NormalizedPhoto {
        guard data.count <= inputByteLimit else { throw PassArtworkError.sourceTooLarge }
        guard let image = UIImage(data: data), let cgImage = image.cgImage else {
            throw PassArtworkError.unsupportedImage
        }
        guard cgImage.width <= pixelLimit / max(1, cgImage.height) else {
            throw PassArtworkError.lowMemory
        }
        let swapsDimensions: Bool
        switch image.imageOrientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            swapsDimensions = true
        default:
            swapsDimensions = false
        }
        let sourceWidth = swapsDimensions ? cgImage.height : cgImage.width
        let sourceHeight = swapsDimensions ? cgImage.width : cgImage.height
        let longestSide = max(sourceWidth, sourceHeight)
        let resizeFactor = min(1, 1_800 / CGFloat(longestSide))
        let targetSize = CGSize(
            width: max(1, (CGFloat(sourceWidth) * resizeFactor).rounded()),
            height: max(1, (CGFloat(sourceHeight) * resizeFactor).rounded())
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let normalized = renderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: targetSize))
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        for quality in [0.88, 0.78, 0.68, 0.58] {
            if let output = normalized.jpegData(compressionQuality: quality), output.count <= maximumBytes {
                return NormalizedPhoto(
                    data: output,
                    width: Int(targetSize.width),
                    height: Int(targetSize.height)
                )
            }
        }
        throw PassArtworkError.outputTooLarge
    }

    static func preparePassArt(_ draft: PassDraft) throws -> Data? {
        guard let data = draft.imageData else { return nil }
        let source = try normalizePhoto(data).data
        guard let uiImage = UIImage(data: source), let ciImage = CIImage(data: source) else {
            throw PassArtworkError.unsupportedImage
        }
        let context = CIContext(options: [.useSoftwareRenderer: false])
        let controls = CIFilter.colorControls()
        controls.inputImage = ciImage
        controls.brightness = Float(draft.imageBrightness)
        controls.contrast = Float(draft.imageContrast)
        guard var filtered = controls.outputImage else {
            throw PassArtworkError.unsupportedImage
        }
        if draft.imageBlur > 0 {
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = filtered
            blur.radius = Float(draft.imageBlur)
            guard let result = blur.outputImage else { throw PassArtworkError.unsupportedImage }
            filtered = result.cropped(to: ciImage.extent)
        }
        guard let transformed = context.createCGImage(filtered, from: ciImage.extent) else {
            throw PassArtworkError.unsupportedImage
        }
        let adjustedImage = UIImage(cgImage: transformed, scale: 1, orientation: .up)
        let artSize = CGSize(width: 1_080, height: 390)
        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = 1
        rendererFormat.opaque = true
        let renderer = UIGraphicsImageRenderer(size: artSize, format: rendererFormat)
        let rendered = renderer.image { rendererContext in
            let frame = CGRect(origin: .zero, size: artSize)
            UIColor(hex: draft.backgroundHex).setFill()
            UIRectFill(frame)
            let scale = max(artSize.width / uiImage.size.width, artSize.height / uiImage.size.height) * draft.imageScale
            let size = CGSize(width: uiImage.size.width * scale, height: uiImage.size.height * scale)
            let rect = CGRect(
                x: (artSize.width - size.width) / CGFloat(2) + draft.imageOffsetX,
                y: (artSize.height - size.height) / CGFloat(2) + draft.imageOffsetY,
                width: size.width,
                height: size.height
            )
            adjustedImage.draw(in: rect)
            if let space = CGColorSpace(name: CGColorSpace.sRGB),
               let gradient = CGGradient(
                   colorsSpace: space,
                   colors: [
                       UIColor(hex: draft.backgroundHex)
                           .withAlphaComponent(min(1, draft.gradientStrength + 0.24)).cgColor,
                       UIColor(hex: draft.backgroundHex)
                           .withAlphaComponent(draft.gradientStrength).cgColor
                   ] as CFArray,
                   locations: [0, 1]
               ) {
                rendererContext.cgContext.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: artSize.width, y: artSize.height),
                    options: []
                )
            }
        }
        for quality in [0.88, 0.78, 0.68, 0.58] {
            if let output = rendered.jpegData(compressionQuality: quality),
               output.count <= PassValidator.imageByteLimit {
                return output
            }
        }
        throw PassArtworkError.outputTooLarge
    }
}

private extension UIColor {
    convenience init(hex: String) {
        let value = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let number = UInt64(value, radix: 16) ?? 0x40356F
        self.init(
            red: CGFloat((number >> 16) & 0xFF) / 255,
            green: CGFloat((number >> 8) & 0xFF) / 255,
            blue: CGFloat(number & 0xFF) / 255,
            alpha: 1
        )
    }
}
