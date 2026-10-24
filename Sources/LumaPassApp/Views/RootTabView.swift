import SwiftUI
import UIKit

struct RootTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedTab = AppTab.home
    @State private var showingNewPass = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView(onCreate: { showingNewPass = true }, onExplore: { selectedTab = .explore })
            }
            .tabItem { Label("Inicio", systemImage: "sparkles") }
            .tag(AppTab.home)

            NavigationStack {
                CreateFlowView()
            }
            .tabItem { Label("Crear", systemImage: "plus.app") }
            .tag(AppTab.create)

            NavigationStack {
                ExploreView()
            }
            .tabItem { Label("Explorar", systemImage: "square.grid.2x2") }
            .tag(AppTab.explore)

            NavigationStack {
                DesignsView()
            }
            .tabItem { Label("Mis diseños", systemImage: "rectangle.stack") }
            .tag(AppTab.designs)

            NavigationStack {
                ProfileView()
            }
            .tabItem { Label("Perfil", systemImage: "person.crop.circle") }
            .tag(AppTab.profile)
        }
        .sheet(isPresented: $showingNewPass) {
            NavigationStack {
                CreateFlowView()
            }
        }
        .alert(item: Binding(
            get: { appState.notice },
            set: { appState.notice = $0 }
        )) { notice in
            Alert(
                title: Text(notice.isError ? "No se pudo completar" : "LumaPass"),
                message: Text(notice.message),
                dismissButton: .default(Text("Entendido"))
            )
        }
        .onChange(of: selectedTab) {
            if reduceMotion {
                UISelectionFeedbackGenerator().selectionChanged()
            } else {
                withAnimation(.snappy(duration: 0.28)) {
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }
        }
    }
}

private enum AppTab: Hashable {
    case home, create, explore, designs, profile
}
