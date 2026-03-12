import SwiftUI

struct AppShellView: View {
    private static let hardcodedBackendURL = "wss://lisa.taild3cb8f.ts.net"
    private static let hardcodedAuthToken = "mindblade"

    @EnvironmentObject private var appState: AppState
    @State private var connectionManager: ConnectionManager?
    @State private var displayedSecret = Self.hardcodedAuthToken
    @State private var connectErrorMessage: String?

    var body: some View {
        Group {
            if let connectionManager, appState.connectionStatus == .connected {
                TabView {
                    PushToTalkView(connectionManager: connectionManager)
                        .tabItem {
                            Label("Talk", systemImage: "mic.fill")
                        }

                    TranscriptView()
                        .tabItem {
                            Label("Session", systemImage: "text.bubble")
                        }
                }
            } else {
                ConnectGatewayView(
                    displayedSecret: $displayedSecret,
                    isConnecting: appState.connectionStatus == .connecting,
                    errorMessage: connectErrorMessage ?? appState.errorMessage,
                    onConnect: { Task { await connectTapped() } }
                )
            }
        }
    }

    @MainActor
    private func connectTapped() async {
        connectErrorMessage = nil
        appState.errorMessage = nil

        guard let url = URL(string: Self.hardcodedBackendURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "wss",
              url.host != nil else {
            connectErrorMessage = "Hardcoded backend URL is invalid."
            return
        }

        let manager = ConnectionManager(
            surface: .iphone,
            transport: WebSocketVoiceClient(backendURL: url),
            sessionAuthToken: Self.hardcodedAuthToken
        )
        await manager.connectIfNeeded(appState: appState)

        if appState.connectionStatus == .connected {
            connectionManager = manager
            connectErrorMessage = nil
        } else {
            connectionManager = nil
            connectErrorMessage = appState.errorMessage ?? "Could not connect to backend."
        }
    }
}

private struct ConnectGatewayView: View {
    @Binding var displayedSecret: String
    let isConnecting: Bool
    let errorMessage: String?
    let onConnect: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            Text("Welcome to LisaMindblade")
                .font(.title.bold())
                .multilineTextAlignment(.center)

            Text("Backend endpoint is hardcoded for this build.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Text("wss://lisa.taild3cb8f.ts.net")
                .font(.subheadline.monospaced())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)

            SecureField("Secret", text: $displayedSecret)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 20)
                .disabled(true)

            Button {
                onConnect()
            } label: {
                if isConnecting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Connect")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isConnecting)
            .padding(.horizontal, 20)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer()
        }
    }
}
