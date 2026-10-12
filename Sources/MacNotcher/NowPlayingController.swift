import AppKit
import Observation
import SwiftUI

struct NowPlayingInfo: Equatable {
    var title: String
    var artist: String
    var album: String
    var bundleIdentifier: String?
    var isPlaying: Bool
    var duration: Double
    /// Elapsed time as of `timestamp`.
    var elapsed: Double
    var timestamp: Date
    var rate: Double

    /// Elapsed time interpolated locally, so the scrubber moves without new updates.
    func elapsed(at date: Date) -> Double {
        guard isPlaying else { return elapsed }
        let t = elapsed + date.timeIntervalSince(timestamp) * rate
        return duration > 0 ? min(max(t, 0), duration) : max(t, 0)
    }
}

/// System-wide now playing info, read through mediaremote-adapter.
///
/// MediaRemote is blocked for third-party apps since macOS 15.4, so we run the
/// adapter's Perl script with the Apple-signed /usr/bin/perl, which loads the bundled
/// MediaRemoteAdapter.framework and streams JSON lines back over stdout.
@Observable
@MainActor
final class NowPlayingController {
    private(set) var info: NowPlayingInfo?
    private(set) var artwork: NSImage?
    /// A brightened version of the artwork's average color, for tinting.
    private(set) var accentColor: Color = .white
    /// Set when the adapter can't be found or keeps failing.
    private(set) var adapterError: String?

    var isPlaying: Bool { info?.isPlaying == true }

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var stopping = false
    @ObservationIgnored private var restartDelay: TimeInterval = 1
    @ObservationIgnored private var artworkKey: Int?

    private enum Command: Int {
        case togglePlayPause = 2, nextTrack = 4, previousTrack = 5
    }

    private var adapterPaths: (script: String, framework: String)? {
        guard let resources = Bundle.main.resourceURL,
              let frameworks = Bundle.main.privateFrameworksURL else { return nil }
        let script = resources.appendingPathComponent("mediaremote-adapter.pl").path
        let framework = frameworks.appendingPathComponent("MediaRemoteAdapter.framework").path
        let fm = FileManager.default
        guard fm.fileExists(atPath: script), fm.fileExists(atPath: framework) else { return nil }
        return (script, framework)
    }

    // MARK: - Stream lifecycle

    func start() {
        stopping = false
        guard process == nil else { return }
        guard let paths = adapterPaths else {
            adapterError = "mediaremote-adapter isn't bundled. Build with build.sh."
            return
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [paths.script, paths.framework, "stream", "--no-diff", "--micros", "--debounce=100"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice

        let reader = LineReader { [weak self] line in
            guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let payload = json["payload"] as? [String: Any] else { return }
            DispatchQueue.main.async { self?.apply(payload) }
        }
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                reader.append(data)
            }
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.processEnded() }
        }

        do {
            try p.run()
            process = p
        } catch {
            adapterError = "Couldn't start the media adapter: \(error.localizedDescription)"
        }
    }

    func stop() {
        stopping = true
        process?.terminate()
        process = nil
    }

    private func processEnded() {
        process = nil
        guard !stopping else { return }
        // Restart with backoff, so a crash or a macOS change doesn't spin the CPU.
        let delay = restartDelay
        restartDelay = min(restartDelay * 2, 60)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.start() }
    }

    // MARK: - Parsing

    private func apply(_ payload: [String: Any]) {
        restartDelay = 1
        adapterError = nil

        guard let title = payload["title"] as? String, !title.isEmpty else {
            info = nil
            setArtwork(nil)
            return
        }

        func number(_ key: String) -> Double? { (payload[key] as? NSNumber)?.doubleValue }

        let isPlaying = payload["playing"] as? Bool ?? false
        let timestamp = number("timestampEpochMicros").map { Date(timeIntervalSince1970: $0 / 1_000_000) } ?? Date()
        let rate = number("playbackRate") ?? 1
        info = NowPlayingInfo(
            title: title,
            artist: payload["artist"] as? String ?? "",
            album: payload["album"] as? String ?? "",
            bundleIdentifier: (payload["parentApplicationBundleIdentifier"] as? String) ?? (payload["bundleIdentifier"] as? String),
            isPlaying: isPlaying,
            duration: (number("durationMicros") ?? 0) / 1_000_000,
            elapsed: (number("elapsedTimeMicros") ?? 0) / 1_000_000,
            timestamp: timestamp,
            rate: rate > 0 ? rate : 1
        )
        setArtwork(payload["artworkData"] as? String)
    }

    private func setArtwork(_ base64: String?) {
        // --no-diff resends the artwork on every update, so skip decoding when unchanged.
        let key = base64?.hashValue
        guard key != artworkKey else { return }
        artworkKey = key
        guard let base64, let data = Data(base64Encoded: base64), let image = NSImage(data: data) else {
            artwork = nil
            accentColor = .white
            return
        }
        artwork = image
        accentColor = image.accentColor.map(Color.init(nsColor:)) ?? .white
    }

    // MARK: - Controls

    func togglePlayPause() {
        send(.togglePlayPause)
        // Update right away rather than waiting for the stream to catch up.
        guard var i = info else { return }
        let now = Date()
        i.elapsed = i.elapsed(at: now)
        i.timestamp = now
        i.isPlaying.toggle()
        info = i
    }

    func next() { send(.nextTrack) }
    func previous() { send(.previousTrack) }

    func seek(to seconds: Double) {
        runAdapter(["seek", String(Int(seconds * 1_000_000))])
        guard var i = info else { return }
        i.elapsed = seconds
        i.timestamp = Date()
        info = i
    }

    func openSourceApp() {
        guard let id = info?.bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    private func send(_ command: Command) {
        runAdapter(["send", String(command.rawValue)])
    }

    private func runAdapter(_ args: [String]) {
        guard let paths = adapterPaths else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [paths.script, paths.framework] + args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }
}

/// Splits a byte stream into newline-terminated lines. Only touched from the pipe's
/// readability handler, which runs serially.
private final class LineReader: @unchecked Sendable {
    private var buffer = Data()
    private let onLine: (Data) -> Void

    init(onLine: @escaping (Data) -> Void) { self.onLine = onLine }

    func append(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if !line.isEmpty { onLine(Data(line)) }
        }
    }
}

private extension NSImage {
    /// Average color of the image, brightened so it reads on black.
    var accentColor: NSColor? {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn: Bool = pixel.withUnsafeMutableBytes { bytes in
            guard let ctx = CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }
        let color = NSColor(srgbRed: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                            blue: CGFloat(pixel[2]) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return NSColor(hue: h, saturation: min(s, 0.7), brightness: max(b, 0.85), alpha: 1)
    }
}
