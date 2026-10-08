import AVFoundation
import CoreGraphics
import CoreText
import Foundation
import ImageIO

public enum RenderBackground: @unchecked Sendable {
    case color
    case image(CGImage)
    case video(URL)
}

public struct RenderRequest: @unchecked Sendable {
    public var title: String
    public var words: [WordTiming]          // words of the full spoken text (hook + script + outro)
    public var audio: URL
    public var duration: Double             // audio duration
    public var platform: Platform
    public var background: RenderBackground
    public var output: URL
    public init(title: String, words: [WordTiming], audio: URL, duration: Double, platform: Platform, background: RenderBackground, output: URL) {
        self.title = title; self.words = words; self.audio = audio; self.duration = duration
        self.platform = platform; self.background = background; self.output = output
    }
}

public enum RenderError: LocalizedError {
    case writer(String)
    public var errorDescription: String? { if case .writer(let m) = self { return "render_failed: \(m)" }; return nil }
}

/// Native render (AVFoundation + CoreGraphics): no ffmpeg or external dependencies.
public enum Renderer {
    static let fps = 30
    static let yellow = CGColor(red: 1, green: 0.898, blue: 0, alpha: 1)

    public static func render(_ req: RenderRequest, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        try await Job(req, progress).run()
    }

    // MARK: - Image utilities

    public static func loadImage(at url: URL, maxSize: Int = 2400) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: maxSize]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    static func context(_ w: Int, _ h: Int) -> CGContext {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.interpolationQuality = .high
        return ctx
    }

    /// Fills `rect` with the image, cropping the excess (like object-fit: cover).
    static func drawCover(_ img: CGImage, in ctx: CGContext, rect: CGRect) {
        let s = max(rect.width / CGFloat(img.width), rect.height / CGFloat(img.height))
        let w = CGFloat(img.width) * s, h = CGFloat(img.height) * s
        ctx.saveGState(); ctx.clip(to: rect)
        ctx.draw(img, in: CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h))
        ctx.restoreGState()
    }

    // MARK: - Text

    static func font(_ names: [String], size: CGFloat) -> CTFont {
        for n in names { let f = CTFontCreateWithName(n as CFString, size, nil); if (CTFontCopyPostScriptName(f) as String).lowercased().contains(n.lowercased().replacingOccurrences(of: " ", with: "")) { return f } }
        return CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
    }

    static func line(_ text: String, font: CTFont) -> (CTLine, CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font,
                                                    NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true]
        let l = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        return (l, CGFloat(CTLineGetTypographicBounds(l, nil, nil, nil)))
    }

    // MARK: - Render job

    private final class Job: @unchecked Sendable {
        let req: RenderRequest, progress: @Sendable (Double) -> Void
        let W: Int, H: Int
        let total: Double
        var staticBase: CGImage?          // pre-composited background (color / image)
        var titleLayer: CGImage?
        var videoSource: LoopingVideo?
        let capFont: CTFont

        init(_ r: RenderRequest, _ p: @escaping @Sendable (Double) -> Void) {
            req = r; progress = p; W = r.platform.width; H = r.platform.height
            total = r.duration + 0.5
            capFont = Renderer.font(["Impact", "Arial Black", "Helvetica Neue Condensed Black"], size: r.platform.captionSize)
        }

        func run() async throws {
            try? FileManager.default.removeItem(at: req.output)
            buildLayers()
            let writer = try AVAssetWriter(outputURL: req.output, fileType: .mp4)
            let bitrate = req.platform.orientation == .vertical ? 8_000_000 : 10_000_000
            let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: W, AVVideoHeightKey: H,
                AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel]])
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: vIn, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: W, kCVPixelBufferHeightKey as String: H])
            let aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVNumberOfChannelsKey: 1, AVSampleRateKey: 44100, AVEncoderBitRateKey: 128_000])
            vIn.expectsMediaDataInRealTime = false; aIn.expectsMediaDataInRealTime = false
            guard writer.canAdd(vIn), writer.canAdd(aIn) else { throw RenderError.writer("cannot add inputs") }
            writer.add(vIn); writer.add(aIn)

            let audioAsset = AVURLAsset(url: req.audio)
            let reader = try AVAssetReader(asset: audioAsset)
            guard let track = try await audioAsset.loadTracks(withMediaType: .audio).first else { throw RenderError.writer("no audio track") }
            let aOut = AVAssetReaderTrackOutput(track: track, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1])
            reader.add(aOut)
            guard writer.startWriting(), reader.startReading() else { throw RenderError.writer(writer.error?.localizedDescription ?? reader.error?.localizedDescription ?? "start") }
            writer.startSession(atSourceTime: .zero)

            let frames = Int((total * Double(fps)).rounded(.up))
            let group = DispatchGroup()
            let vq = DispatchQueue(label: "yaikus.render.video"), aq = DispatchQueue(label: "yaikus.render.audio")
            let counter = Counter()

            group.enter()
            vIn.requestMediaDataWhenReady(on: vq) { [self] in
                while vIn.isReadyForMoreMediaData {
                    let index = counter.value
                    if index >= frames { vIn.markAsFinished(); group.leave(); return }
                    guard let pool = adaptor.pixelBufferPool else { continue }
                    var pb: CVPixelBuffer?
                    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
                    guard let buf = pb else { continue }
                    CVPixelBufferLockBaseAddress(buf, [])
                    let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buf), width: W, height: H, bitsPerComponent: 8,
                                        bytesPerRow: CVPixelBufferGetBytesPerRow(buf), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
                    ctx.interpolationQuality = .high
                    drawFrame(ctx, at: Double(index) / Double(fps))
                    CVPixelBufferUnlockBaseAddress(buf, [])
                    if !adaptor.append(buf, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: CMTimeScale(fps))) {
                        vIn.markAsFinished(); group.leave(); return
                    }
                    counter.value += 1
                    if (index + 1) % 15 == 0 { progress(Double(index + 1) / Double(frames) * 0.97) }
                }
            }
            group.enter()
            aIn.requestMediaDataWhenReady(on: aq) {
                while aIn.isReadyForMoreMediaData {
                    if let sb = aOut.copyNextSampleBuffer() { if !aIn.append(sb) { aIn.markAsFinished(); group.leave(); return } }
                    else { aIn.markAsFinished(); group.leave(); return }
                }
            }
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in group.notify(queue: .global()) { c.resume() } }
            await writer.finishWriting()
            guard writer.status == .completed else { throw RenderError.writer(writer.error?.localizedDescription ?? "status \(writer.status.rawValue)") }
            progress(1)
        }

        // MARK: static layers
        func buildLayers() {
            let p = req.platform
            // title (pink, at the top)
            let tctx = Renderer.context(W, H)
            let tf = Renderer.font(["Arial Bold", "Arial-BoldMT", "Helvetica Neue Bold"], size: p.titleSize)
            let lines = wrap(req.title.uppercased(), font: tf, maxWidth: CGFloat(W) - 140)
            let lh = p.titleSize * 1.28, pad: CGFloat = 14
            var y = CGFloat(H) - p.titleMargin - lh
            for (l, w) in lines {
                let box = CGRect(x: (CGFloat(W) - w) / 2 - pad, y: y - 12, width: w + pad * 2, height: lh)
                tctx.setFillColor(CGColor(red: 0.94, green: 0.125, blue: 0.627, alpha: 1)); tctx.fill(box)
                tctx.setFillColor(CGColor(gray: 1, alpha: 1)); tctx.textPosition = CGPoint(x: (CGFloat(W) - w) / 2, y: y + 6)
                CTLineDraw(l, tctx)
                y -= lh
            }
            titleLayer = tctx.makeImage()

            switch req.background {
            case .color:
                let c = Renderer.context(W, H); c.setFillColor(CGColor(red: 0.078, green: 0.102, blue: 0.2, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: W, height: H))
                staticBase = c.makeImage()
            case .image(let img):
                let c = Renderer.context(W, H); composeBackdrop(img, into: c); staticBase = c.makeImage()
            case .video(let url):
                videoSource = LoopingVideo(url: url)
            }
        }

        /// Blurred background (cover) + a sharp, centered image.
        func composeBackdrop(_ img: CGImage, into ctx: CGContext) {
            let full = CGRect(x: 0, y: 0, width: W, height: H)
            // cheap blur: shrink a lot, then scale back up with high-quality interpolation
            var small = Renderer.context(max(W / 18, 8), max(H / 18, 8))
            Renderer.drawCover(img, in: small, rect: CGRect(x: 0, y: 0, width: small.width, height: small.height))
            let mid = Renderer.context(W / 6, H / 6)
            mid.draw(small.makeImage()!, in: CGRect(x: 0, y: 0, width: mid.width, height: mid.height))
            small = mid
            ctx.draw(small.makeImage()!, in: full)
            ctx.setFillColor(CGColor(gray: 0, alpha: 0.18)); ctx.fill(full)
            let p = req.platform
            let aspect = CGFloat(img.width) / CGFloat(img.height)
            let size: CGSize = p.orientation == .vertical ? CGSize(width: 1000, height: 1000 / aspect) : CGSize(width: 640 * aspect, height: 640)
            let dy: CGFloat = p.orientation == .vertical ? 120 : -10        // + = up (origin is bottom-left)
            ctx.draw(img, in: CGRect(x: (CGFloat(W) - size.width) / 2, y: (CGFloat(H) - size.height) / 2 + dy, width: size.width, height: size.height))
        }

        func wrap(_ text: String, font: CTFont, maxWidth: CGFloat) -> [(CTLine, CGFloat)] {
            var out: [(CTLine, CGFloat)] = [], cur = ""
            for w in text.split(separator: " ") {
                let trial = cur.isEmpty ? String(w) : cur + " " + w
                if Renderer.line(trial, font: font).1 > maxWidth, !cur.isEmpty { out.append(Renderer.line(cur, font: font)); cur = String(w) } else { cur = trial }
            }
            if !cur.isEmpty { out.append(Renderer.line(cur, font: font)) }
            return out
        }

        // MARK: frame
        func drawFrame(_ ctx: CGContext, at t: Double) {
            let full = CGRect(x: 0, y: 0, width: W, height: H)
            if let base = staticBase { ctx.draw(base, in: full) }
            else if let v = videoSource {
                if let frame = v.frame(at: t) { composeBackdrop(frame, into: ctx) }
                else { ctx.setFillColor(CGColor(gray: 0.1, alpha: 1)); ctx.fill(full) }
            }
            if let tl = titleLayer { ctx.draw(tl, in: full) }
            drawCaption(ctx, at: t)
        }

        func drawCaption(_ ctx: CGContext, at t: Double) {
            let words = req.words
            guard !words.isEmpty else { return }
            let per = req.platform.wordsPerChunk
            // active word: the last one whose start has passed (it stays through short pauses)
            var active = 0
            for (i, w) in words.enumerated() where w.start <= t { active = i }
            if t > words[active].end + 0.6 && active == words.count - 1 { return }
            let chunk = active / per
            let group = Array(words[(chunk * per)..<min(chunk * per + per, words.count)])
            let activeInChunk = active - chunk * per
            let maxW = CGFloat(W) - 120
            let space = Renderer.line(" ", font: capFont).1 * 1.1
            // split the words into lines that fit
            var lines: [[(String, CGFloat, Int)]] = [[]], widths: [CGFloat] = [0]
            for (j, w) in group.enumerated() {
                let word = w.word.uppercased(), wd = Renderer.line(word, font: capFont).1
                if widths[widths.count - 1] + (lines[lines.count - 1].isEmpty ? 0 : space) + wd > maxW, !lines[lines.count - 1].isEmpty { lines.append([]); widths.append(0) }
                widths[widths.count - 1] += (lines[lines.count - 1].isEmpty ? 0 : space) + wd
                lines[lines.count - 1].append((word, wd, j))
            }
            let lh = req.platform.captionSize * 1.12
            ctx.setLineJoin(.round)
            for pass in 0..<2 {                                   // 0: outline, 1: fill
                for (li, ln) in lines.enumerated() {
                    var x = (CGFloat(W) - widths[li]) / 2
                    let y = req.platform.captionMargin + CGFloat(lines.count - 1 - li) * lh
                    for (word, wd, j) in ln {
                        let (l, _) = Renderer.line(word, font: capFont)
                        ctx.textPosition = CGPoint(x: x, y: y)
                        if pass == 0 { ctx.setTextDrawingMode(.stroke); ctx.setLineWidth(req.platform.captionSize * 0.16); ctx.setStrokeColor(CGColor(gray: 0, alpha: 1)) }
                        else { ctx.setTextDrawingMode(.fill); ctx.setFillColor(j == activeInChunk ? Renderer.yellow : CGColor(gray: 1, alpha: 1)) }
                        CTLineDraw(l, ctx)
                        x += wd + space
                    }
                }
            }
            ctx.setTextDrawingMode(.fill)
        }
    }

    final class Counter: @unchecked Sendable { var value = 0 }

    // MARK: - Looping background video

    final class LoopingVideo: @unchecked Sendable {
        let url: URL
        var reader: AVAssetReader?
        var output: AVAssetReaderTrackOutput?
        var current: (pts: Double, image: CGImage)?
        var next: (pts: Double, image: CGImage)?
        var loopDuration: Double = 0
        var offset: Double = 0

        init(url: URL) {
            self.url = url
            loopDuration = max(AVURLAsset(url: url).duration.seconds, 0.1)
            restart()
        }

        func restart() {
            let asset = AVURLAsset(url: url)
            guard let track = asset.tracks(withMediaType: .video).first, let r = try? AVAssetReader(asset: asset) else { return }
            let o = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            r.add(o); r.startReading()
            reader = r; output = o; current = nil; next = readOne()
        }

        func readOne() -> (Double, CGImage)? {
            guard let o = output, let sb = o.copyNextSampleBuffer(), let px = CMSampleBufferGetImageBuffer(sb) else { return nil }
            CVPixelBufferLockBaseAddress(px, .readOnly); defer { CVPixelBufferUnlockBaseAddress(px, .readOnly) }
            let ctx = CGContext(data: CVPixelBufferGetBaseAddress(px), width: CVPixelBufferGetWidth(px), height: CVPixelBufferGetHeight(px), bitsPerComponent: 8,
                                bytesPerRow: CVPixelBufferGetBytesPerRow(px), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            guard let img = ctx?.makeImage() else { return nil }
            return (CMSampleBufferGetPresentationTimeStamp(sb).seconds, img)
        }

        /// Video frame for timeline instant t (loops when it reaches the end).
        func frame(at t: Double) -> CGImage? {
            let local = t - offset
            if local >= loopDuration { offset += loopDuration; restart(); return frame(at: t) }
            while let n = next, n.pts <= local { current = n; next = readOne() }
            if current == nil, let n = next { current = n }
            if next == nil && current != nil && local >= current!.pts + 0.5 { offset += max(local, 0.1); restart() }
            return current?.image
        }
    }
}
