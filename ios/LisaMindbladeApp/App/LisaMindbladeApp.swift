import SwiftUI

@main
struct LisaMindbladeApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .environmentObject(appState)
        }
    }
}
