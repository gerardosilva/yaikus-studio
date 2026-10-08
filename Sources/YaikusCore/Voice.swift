import AVFoundation
import Foundation

public struct WordTiming: Hashable, Sendable {
    public var word: String
    public var start: Double
    public var end: Double
    public init(_ word: String, _ start: Double, _ end: Double) { self.word = word; self.start = start; self.end = end }
}

public struct SynthesizedVoice: Sendable {
    public var url: URL
    public var words: [WordTiming]
    public var duration: Double
}

public enum VoiceError: LocalizedError, Sendable {
    case keyMissing, keyInvalid, voiceIdMissing, failed(String)
    public var errorDescription: String? {
        switch self {
        case .keyMissing: return "voice_key_missing"
        case .keyInvalid: return "voice_key_invalid"
        case .voiceIdMissing: return "voice_id_missing"
        case .failed(let m): return "voice_failed: \(m)"
        }
    }
}

/// Voice: the user connects their own service. The app bundles none.
///   system      Mac voice (AVSpeechSynthesizer): offline, no keys
///   openai      any API compatible with /audio/speech
///   elevenlabs  ElevenLabs (with per-character timings → exact captions)
/// Without provider timings, they are estimated by length and anchored to the audio's real pauses.
public enum VoiceService {
    public static func synthesize(text: String, language: String, voiceName: String, settings: VoiceSettings,
                                  apiKey: String, into dir: URL) async throws -> SynthesizedVoice {
        Paths.ensure(dir)
        var words: [WordTiming]?
        let url: URL
        switch settings.provider {
        case .system:
            url = dir.appendingPathComponent("voice.caf")
            try await SystemSpeech.synthesize(text: text, language: language, voiceName: voiceName, to: url)
        case .openai:
            url = dir.appendingPathComponent("voice.mp3")
            try await openAI(text: text, voiceName: voiceName, settings: settings, apiKey: apiKey, to: url)
        case .elevenlabs:
            url = dir.appendingPathComponent("voice.mp3")
            words = try await elevenLabs(text: text, voiceName: voiceName, settings: settings, apiKey: apiKey, to: url)
        }
        let total = try await AudioAnalysis.duration(of: url)
        guard total > 0 else { throw VoiceError.failed("empty audio") }
        let finalWords = words ?? Aligner.align(Aligner.estimate(text: text, total: total), silences: AudioAnalysis.silences(of: url, total: total), total: total)
        return SynthesizedVoice(url: url, words: finalWords, duration: total)
    }

    // MARK: OpenAI-compatible
    static func openAI(text: String, voiceName: String, settings: VoiceSettings, apiKey: String, to url: URL) async throws {
        let base = settings.baseURL.isEmpty ? "https://api.openai.com/v1" : settings.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if apiKey.isEmpty && base.contains("api.openai.com") { throw VoiceError.keyMissing }
        var req = URLRequest(url: URL(string: base + "/audio/speech")!, timeoutInterval: 180)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty { req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": settings.model.isEmpty ? "tts-1" : settings.model,
            "voice": voiceName.isEmpty ? "alloy" : voiceName, "input": text, "response_format": "mp3"])
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 || code == 403 { throw VoiceError.keyInvalid }
        guard code == 200 else { throw VoiceError.failed("HTTP \(code)") }
        try data.write(to: url)
    }

    // MARK: ElevenLabs
    static func elevenLabs(text: String, voiceName: String, settings: VoiceSettings, apiKey: String, to url: URL) async throws -> [WordTiming]? {
        if apiKey.isEmpty { throw VoiceError.keyMissing }
        if voiceName.isEmpty { throw VoiceError.voiceIdMissing }
        var comps = URLComponents(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceName)/with-timestamps")!
        comps.queryItems = [URLQueryItem(name: "output_format", value: "mp3_44100_128")]
        var req = URLRequest(url: comps.url!, timeoutInterval: 180)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["text": text, "model_id": settings.model.isEmpty ? "eleven_multilingual_v2" : settings.model])
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 || code == 403 { throw VoiceError.keyInvalid }
        guard code == 200, let j = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let b64 = j["audio_base64"] as? String, let audio = Data(base64Encoded: b64) else { throw VoiceError.failed("HTTP \(code)") }
        try audio.write(to: url)
        if let al = j["alignment"] as? [String: Any], let chars = al["characters"] as? [String],
           let st = al["character_start_times_seconds"] as? [Double], let en = al["character_end_times_seconds"] as? [Double] {
            return wordsFromCharacters(chars, st, en)
        }
        return nil
    }

    static func wordsFromCharacters(_ chars: [String], _ starts: [Double], _ ends: [Double]) -> [WordTiming] {
        var out: [WordTiming] = [], cur = "", ws = 0.0, we = 0.0
        for (i, ch) in chars.enumerated() where i < starts.count && i < ends.count {
            if ch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !cur.isEmpty { out.append(WordTiming(cur, ws, we)); cur = "" }
                continue
            }
            if cur.isEmpty { ws = starts[i] }
            cur += ch; we = ends[i]
        }
        if !cur.isEmpty { out.append(WordTiming(cur, ws, we)) }
        return out
    }
}

// MARK: - Mac voice

public enum SystemSpeech {
    /// Novelty voices that are never picked automatically.
    static let novelty: Set<String> = ["Albert", "Bad News", "Bahh", "Bells", "Boing", "Bubbles", "Cellos", "Good News", "Jester", "Organ",
                                      "Superstar", "Trinoids", "Whisper", "Wobble", "Zarvox", "Grandma", "Grandpa", "Fred", "Junior", "Kathy", "Ralph"]
    static let preferred: [String: [String]] = [
        "es": ["Paulina", "Mónica", "Eddy (Spanish (Mexico))", "Flo (Spanish (Mexico))", "Reed (Spanish (Mexico))", "Jorge"],
        "en": ["Samantha", "Ava", "Alex", "Eddy (English (US))", "Flo (English (US))", "Allison"],
    ]

    public struct VoiceInfo: Hashable, Identifiable, Sendable {
        public var id: String { name }
        public var name: String
        public var language: String
    }

    public static func installedVoices() -> [VoiceInfo] {
        AVSpeechSynthesisVoice.speechVoices().filter { !novelty.contains($0.name) }
            .map { VoiceInfo(name: $0.name, language: $0.language) }
            .sorted { $0.name < $1.name }
    }

    static func pick(_ requested: String, language: String) -> AVSpeechSynthesisVoice? {
        let all = AVSpeechSynthesisVoice.speechVoices()
        if !requested.isEmpty, let v = all.first(where: { $0.name == requested }) { return v }
        let lang = String(language.prefix(2))
        for n in preferred[lang] ?? [] { if let v = all.first(where: { $0.name == n }) { return v } }
        let cands = all.filter { $0.language.lowercased().hasPrefix(lang) && !novelty.contains($0.name) }
        return cands.max(by: { $0.quality.rawValue < $1.quality.rawValue }) ?? AVSpeechSynthesisVoice(language: language)
    }

    public static func synthesize(text: String, language: String, voiceName: String, to url: URL) async throws {
        try? FileManager.default.removeItem(at: url)
        let utt = AVSpeechUtterance(string: text)
        utt.voice = pick(voiceName, language: language)
        let job = Job()
        try await job.run(utterance: utt, url: url)
    }

    /// Keeps the synthesizer alive during synthesis and writes the buffers to a file.
    private final class Job: NSObject, @unchecked Sendable {
        let synth = AVSpeechSynthesizer()
        var file: AVAudioFile?
        var finished = false
        let lock = NSLock()

        func run(utterance: AVSpeechUtterance, url: URL) async throws {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                @Sendable func finish(_ error: Error?) {
                    lock.lock(); defer { lock.unlock() }
                    guard !finished else { return }
                    finished = true
                    if let error { cont.resume(throwing: error) } else { cont.resume() }
                }
                synth.write(utterance) { [self] buffer in
                    guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                    if pcm.frameLength == 0 { finish(nil); return }
                    do {
                        if file == nil { file = try AVAudioFile(forWriting: url, settings: pcm.format.settings) }
                        try file?.write(from: pcm)
                    } catch { finish(VoiceError.failed(error.localizedDescription)) }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 180) { finish(VoiceError.failed("timeout")) }
            }
            file = nil   // closes the file
        }
    }
}
