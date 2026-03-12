import AVFoundation
import Foundation

@MainActor
protocol AudioPlaying {
    var onPlaybackStateChanged: ((Bool) -> Void)? { get set }

    func startSession()
    func playTextChunk(_ text: String, isFinal: Bool)
    func stopSession()
}

@MainActor
final class AVSpeechAudioPlaybackService: NSObject, AudioPlaying {
    private let synthesizer = AVSpeechSynthesizer()
    private var bufferedText: String = ""
    private var selectedVoice: AVSpeechSynthesisVoice?
    private var isPlaybackActive = false
    var onPlaybackStateChanged: ((Bool) -> Void)?
    private static let preferredVoiceNameKey = "LisaMindbladePreferredVoiceName"
    private static let defaultPreferredVoiceName = "Ava"

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func startSession() {
        ConversationAudioSession.shared.activateIfNeeded()
        selectedVoice = Self.resolveBestVoice()
    }

    func playTextChunk(_ text: String, isFinal: Bool) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        if isFinal {
            let buffered = bufferedText.trimmingCharacters(in: .whitespacesAndNewlines)
            let utteranceText: String
            if buffered.isEmpty {
                utteranceText = clean
            } else if normalized(buffered) == normalized(clean) {
                // Avoid repeating the same content when final text duplicates chunks.
                utteranceText = clean
            } else {
                utteranceText = "\(buffered) \(clean)"
            }
            bufferedText = ""
            speak(utteranceText)
        } else {
            bufferedText = [bufferedText, clean].joined(separator: " ")
        }
    }

    func stopSession() {
        bufferedText = ""
        synthesizer.stopSpeaking(at: .immediate)
        updatePlaybackState(false)
    }

    private func speak(_ text: String) {
        guard !text.isEmpty else { return }
        updatePlaybackState(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.voice = selectedVoice
            ?? Self.resolveBestVoice()
            ?? AVSpeechSynthesisVoice(language: Locale.preferredLanguages.first ?? "en-US")
        synthesizer.speak(utterance)
    }

    private func updatePlaybackState(_ active: Bool) {
        guard isPlaybackActive != active else { return }
        isPlaybackActive = active
        onPlaybackStateChanged?(active)
    }

    private func normalized(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func resolveBestVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        guard !voices.isEmpty else { return nil }

        if let explicitVoice = preferredVoice(from: voices) {
            return explicitVoice
        }

        let preferredCodes = Locale.preferredLanguages.map(canonicalLanguageCode)
        for preferred in preferredCodes {
            let exactMatches = voices.filter { canonicalLanguageCode($0.language) == preferred }
            if let voice = bestQualityVoice(from: exactMatches) {
                return voice
            }

            if let preferredBase = preferred.split(separator: "-").first {
                let baseMatches = voices.filter { voice in
                    guard let base = canonicalLanguageCode(voice.language).split(separator: "-").first else {
                        return false
                    }
                    return base == preferredBase
                }
                if let voice = bestQualityVoice(from: baseMatches) {
                    return voice
                }
            }
        }

        return bestQualityVoice(from: voices)
    }

    private static func bestQualityVoice(from voices: [AVSpeechSynthesisVoice]) -> AVSpeechSynthesisVoice? {
        voices.max { lhs, rhs in
            if lhs.quality.rawValue != rhs.quality.rawValue {
                return lhs.quality.rawValue < rhs.quality.rawValue
            }

            let lhsName = lhs.name.lowercased()
            let rhsName = rhs.name.lowercased()
            if lhsName == "zoe", rhsName != "zoe" {
                return false
            }
            if rhsName == "zoe", lhsName != "zoe" {
                return true
            }
            return lhsName < rhsName
        }
    }

    private static func canonicalLanguageCode(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: "-").lowercased()
    }

    private static func preferredVoice(from voices: [AVSpeechSynthesisVoice]) -> AVSpeechSynthesisVoice? {
        let requestedName = (
            UserDefaults.standard.string(forKey: preferredVoiceNameKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        ).flatMap { $0.isEmpty ? nil : $0 } ?? defaultPreferredVoiceName

        return voices.first { voice in
            voice.name.compare(requestedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }
}

extension AVSpeechAudioPlaybackService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if !self.synthesizer.isSpeaking {
                self.updatePlaybackState(false)
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if !self.synthesizer.isSpeaking {
                self.updatePlaybackState(false)
            }
        }
    }
}

@MainActor
final class StubAudioPlaybackService: AudioPlaying {
    var onPlaybackStateChanged: ((Bool) -> Void)?

    func startSession() {
        // No-op.
    }

    func playTextChunk(_ text: String, isFinal: Bool) {
        _ = text
        _ = isFinal
    }

    func stopSession() {
        onPlaybackStateChanged?(false)
        // No-op.
    }
}
