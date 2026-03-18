import AVFoundation
import Foundation

struct SpeechVoiceOption: Identifiable, Equatable {
    let id: String
    let name: String
    let language: String
    let isPersonalVoice: Bool

    var displayName: String {
        if isPersonalVoice {
            return "\(name) (Personal Voice • \(language))"
        }
        return "\(name) (\(language))"
    }
}

@MainActor
protocol AudioPlaying {
    var onPlaybackStateChanged: ((Bool) -> Void)? { get set }

    func startSession()
    func playTextChunk(_ text: String, isFinal: Bool)
    func stopSession()
    func availableVoices() -> [SpeechVoiceOption]
    func selectedVoiceIdentifier() -> String?
    func setPreferredVoice(identifier: String?)
    func requestPersonalVoiceAuthorizationIfNeeded() async
}

@MainActor
final class AVSpeechAudioPlaybackService: NSObject, AudioPlaying {
    private let synthesizer = AVSpeechSynthesizer()
    private var bufferedText: String = ""
    private var selectedVoice: AVSpeechSynthesisVoice?
    private var isPlaybackActive = false
    var onPlaybackStateChanged: ((Bool) -> Void)?

    private static let preferredVoiceIdentifierKey = "LisaMindbladePreferredVoiceIdentifier"
    private static let preferredVoiceNameKey = "LisaMindbladePreferredVoiceName"
    private static let defaultPreferredVoiceName = "Siri Voice 2"

    override init() {
        super.init()
        synthesizer.delegate = self
        selectedVoice = Self.resolveBestVoice()
    }

    func startSession() {
        ConversationAudioSession.shared.activateIfNeeded()
        if selectedVoice == nil {
            selectedVoice = Self.resolveBestVoice()
        }
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

    func availableVoices() -> [SpeechVoiceOption] {
        AVSpeechSynthesisVoice.speechVoices()
            .sorted { lhs, rhs in
                if lhs.name != rhs.name {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.language.localizedCaseInsensitiveCompare(rhs.language) == .orderedAscending
            }
            .map { voice in
                SpeechVoiceOption(
                    id: voice.identifier,
                    name: voice.name,
                    language: voice.language,
                    isPersonalVoice: Self.isPersonalVoice(voice)
                )
            }
    }

    func selectedVoiceIdentifier() -> String? {
        if let selectedVoice {
            return selectedVoice.identifier
        }
        return UserDefaults.standard.string(forKey: Self.preferredVoiceIdentifierKey)
    }

    func setPreferredVoice(identifier: String?) {
        let normalized = identifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let voices = AVSpeechSynthesisVoice.speechVoices()

        guard !normalized.isEmpty else {
            UserDefaults.standard.removeObject(forKey: Self.preferredVoiceIdentifierKey)
            UserDefaults.standard.removeObject(forKey: Self.preferredVoiceNameKey)
            selectedVoice = Self.resolveBestVoice(from: voices)
            return
        }

        guard let matched = voices.first(where: { $0.identifier == normalized }) else {
            selectedVoice = Self.resolveBestVoice(from: voices)
            return
        }

        selectedVoice = matched
        UserDefaults.standard.set(matched.identifier, forKey: Self.preferredVoiceIdentifierKey)
        UserDefaults.standard.set(matched.name, forKey: Self.preferredVoiceNameKey)
    }

    func requestPersonalVoiceAuthorizationIfNeeded() async {
        guard #available(iOS 17.0, *) else { return }

        let status = AVSpeechSynthesizer.personalVoiceAuthorizationStatus
        guard status == .notDetermined else { return }

        await withCheckedContinuation { continuation in
            AVSpeechSynthesizer.requestPersonalVoiceAuthorization { _ in
                continuation.resume()
            }
        }
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
        resolveBestVoice(from: AVSpeechSynthesisVoice.speechVoices())
    }

    private static func resolveBestVoice(from voices: [AVSpeechSynthesisVoice]) -> AVSpeechSynthesisVoice? {
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
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private static func canonicalLanguageCode(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: "-").lowercased()
    }

    private static func isPersonalVoice(_ voice: AVSpeechSynthesisVoice) -> Bool {
        guard #available(iOS 17.0, *) else { return false }
        return voice.voiceTraits.contains(.isPersonalVoice)
    }

    private static func preferredVoice(from voices: [AVSpeechSynthesisVoice]) -> AVSpeechSynthesisVoice? {
        let requestedIdentifier = UserDefaults.standard.string(forKey: preferredVoiceIdentifierKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let requestedIdentifier, !requestedIdentifier.isEmpty {
            if let matchedByIdentifier = voices.first(where: { $0.identifier == requestedIdentifier }) {
                return matchedByIdentifier
            }
        }

        let requestedName = (
            UserDefaults.standard.string(forKey: preferredVoiceNameKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        ).flatMap { $0.isEmpty ? nil : $0 } ?? defaultPreferredVoiceName

        if let exactName = voices.first(where: {
            $0.name.compare(requestedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            return exactName
        }

        if requestedName.compare(defaultPreferredVoiceName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
            let siriLike = voices.filter { voice in
                let lower = voice.name.lowercased()
                return lower.contains("siri") && (lower.contains("voice 2") || lower.contains("2"))
            }
            if let bestSiri = bestQualityVoice(from: siriLike) {
                return bestSiri
            }

            let femaleSiri = voices.filter { voice in
                let identifier = voice.identifier.lowercased()
                return identifier.contains("siri") && identifier.contains("female")
            }
            if let bestFemaleSiri = bestQualityVoice(from: femaleSiri) {
                return bestFemaleSiri
            }
        }

        return nil
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
    }

    func availableVoices() -> [SpeechVoiceOption] {
        []
    }

    func selectedVoiceIdentifier() -> String? {
        nil
    }

    func setPreferredVoice(identifier: String?) {
        _ = identifier
    }

    func requestPersonalVoiceAuthorizationIfNeeded() async {
        // No-op.
    }
}
