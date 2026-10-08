import AVFoundation
import Foundation

public enum AudioAnalysis {
    public static func duration(of url: URL) async throws -> Double {
        let d = try await AVURLAsset(url: url).load(.duration)
        return d.seconds.isFinite ? d.seconds : 0
    }

    /// Internal pauses in the audio (ignores leading and trailing silence). Threshold is relative to the voice level.
    public static func silences(of url: URL, total: Double, minDuration: Double = 0.12) -> [(start: Double, end: Double)] {
        guard let file = try? AVAudioFile(forReading: url) else { return [] }
        let sr = file.processingFormat.sampleRate
        let win = max(Int(sr * 0.01), 1)
        guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(win * 200)) else { return [] }
        var rms: [Float] = []
        while file.framePosition < file.length {
            try? file.read(into: buf)
            guard buf.frameLength > 0, let ch = buf.floatChannelData?[0] else { break }
            var i = 0
            while i + win <= Int(buf.frameLength) {
                var s: Float = 0
                for k in 0..<win { let v = ch[i + k]; s += v * v }
                rms.append((s / Float(win)).squareRoot())
                i += win
            }
        }
        guard rms.count > 10 else { return [] }
        let sorted = rms.sorted()
        let level = sorted[Int(Double(sorted.count) * 0.9)]
        let threshold = max(level * 0.06, 0.0005)
        var out: [(Double, Double)] = []
        var runStart: Int?
        for (i, v) in rms.enumerated() {
            if v < threshold { if runStart == nil { runStart = i } }
            else if let s = runStart {
                let a = Double(s) * 0.01, b = Double(i) * 0.01
                if b - a >= minDuration, a > 0.15, b < total - 0.1 { out.append((a, b)) }
                runStart = nil
            }
        }
        return out
    }
}

/// Estimated word timings + snapping to the real pauses, for voices that provide no timings.
public enum Aligner {
    static func isBoundary(_ w: String) -> Bool { w.last.map { ".!?,;:".contains($0) } ?? false }

    /// Weight by length + a pause after punctuation.
    public static func estimate(text: String, total: Double) -> [WordTiming] {
        let toks = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !toks.isEmpty else { return [] }
        let weights: [Double] = toks.map { t in
            var w = Double(max(t.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?¡¿")).count, 2))
            if let l = t.last { if ".!?".contains(l) { w += 7 } else if ",;:".contains(l) { w += 3 } }
            return w
        }
        let k = total / weights.reduce(0, +)
        var out: [WordTiming] = [], t0 = 0.0
        for (tok, w) in zip(toks, weights) { out.append(WordTiming(tok, t0, t0 + w * k)); t0 += w * k }
        return out
    }

    /// Anchors comma/period breaks to the detected pauses and rescales linearly between anchors.
    public static func align(_ words: [WordTiming], silences: [(start: Double, end: Double)], total: Double) -> [WordTiming] {
        guard words.count > 1, !silences.isEmpty else { return words }
        let bounds = words.indices.dropLast().filter { isBoundary(words[$0].word) }
        var anchors: [(idx: Int, a: Double, b: Double)] = []
        var last = -1
        for s in silences {
            let c = bounds.filter { $0 > last && abs(words[$0].end - s.start) < 1.2 }
            if let i = c.min(by: { abs(words[$0].end - s.start) < abs(words[$1].end - s.start) }) {
                anchors.append((i, s.start, s.end)); last = i
            }
        }
        guard !anchors.isEmpty else { return words }
        var out = words
        let cuts: [(idx: Int, a: Double, b: Double)] = [(-1, 0, 0)] + anchors
        for (n, cut) in cuts.enumerated() {
            let lo = cut.idx + 1
            let hi = n < anchors.count ? anchors[n].idx : words.count - 1
            let a = n < anchors.count ? anchors[n].a : total
            let o0 = words[lo].start, o1 = words[hi].end
            let n0 = n == 0 ? 0 : cut.b
            guard o1 > o0, lo <= hi else { continue }
            for k in lo...hi {
                let s = n0 + (words[k].start - o0) / (o1 - o0) * (a - n0)
                let e = n0 + (words[k].end - o0) / (o1 - o0) * (a - n0)
                out[k] = WordTiming(words[k].word, s, e)
            }
        }
        return out
    }
}
