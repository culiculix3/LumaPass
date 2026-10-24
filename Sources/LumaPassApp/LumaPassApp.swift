import SwiftUI
import UIKit

@main
struct LumaPassApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(appState)
                .preferredColorScheme(appState.useLightAppearance ? .light : .dark)
                .tint(Color.lumaAccent)
        }
    }
}

extension Color {
    static let lumaAccent = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .light {
            return UIColor(red: 0.36, green: 0.25, blue: 0.60, alpha: 1)
        }
        return UIColor(red: 0.78, green: 0.67, blue: 0.96, alpha: 1)
    })
    static let lumaCanvas = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .light {
            return UIColor(red: 0.98, green: 0.977, blue: 0.99, alpha: 1)
        }
        return UIColor(red: 0.075, green: 0.075, blue: 0.10, alpha: 1)
    })
    static let lumaSurface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .light ? .black : .white
    })

    init(hex: String) {
        let value = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let number = UInt64(value, radix: 16) ?? 0x40356F
        self.init(
            .sRGB,
            red: Double((number >> 16) & 0xFF) / 255,
            green: Double((number >> 8) & 0xFF) / 255,
            blue: Double(number & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension View {
    func lumaCard() -> some View {
        padding(18)
            .background(Color.lumaSurface.opacity(0.055), in: RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(Color.lumaSurface.opacity(0.08), lineWidth: 1)
            }
    }
}
