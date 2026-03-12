import SwiftUI

struct TranscriptView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            List {
                Section("Current State") {
                    Text(appState.clientState.rawValue)
                }

                Section("Live Transcript") {
                    if appState.liveTranscript.isEmpty {
                        Text("No transcript yet")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(appState.liveTranscript)
                    }
                }

                Section("Transcript History") {
                    if appState.transcriptHistory.isEmpty {
                        Text("No transcript history")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(appState.transcriptHistory.indices, id: \.self) { index in
                            Text(appState.transcriptHistory[index])
                        }
                    }
                }

                Section("Streaming Assistant") {
                    if appState.streamingAssistantText.isEmpty {
                        Text("No streaming output")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(appState.streamingAssistantText)
                    }
                }

                Section("Assistant History") {
                    if appState.assistantHistory.isEmpty {
                        Text("No assistant responses yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(appState.assistantHistory.indices, id: \.self) { index in
                            Text(appState.assistantHistory[index])
                        }
                    }
                }
            }
            .navigationTitle("Session")
        }
    }
}
