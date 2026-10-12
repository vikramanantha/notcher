import AppKit
import SwiftUI

/// Black notch outline: the top corners flare outward to blend into the screen edge,
/// the bottom corners are rounded.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let t = topRadius
        let b = min(bottomRadius, (rect.width - 2 * t) / 2, rect.height - t)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t), control: CGPoint(x: rect.minX + t, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY), control: CGPoint(x: rect.minX + t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b), control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - t, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

struct NotchView: View {
    let model: NotchModel
    @Namespace private var artworkNamespace

    var body: some View {
        let expanded = model.isExpanded
        let size = expanded ? model.expandedSize : model.collapsedSize
        let topRadius = expanded ? NotchModel.expandedTopRadius : NotchModel.collapsedTopRadius
        let shape = NotchShape(topRadius: topRadius,
                               bottomRadius: expanded ? NotchModel.expandedBottomRadius : NotchModel.collapsedBottomRadius)

        ZStack(alignment: .top) {
            if expanded {
                ExpandedView(model: model, namespace: artworkNamespace)
                    .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .top)))
            } else {
                CollapsedView(model: model, namespace: artworkNamespace)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, topRadius)
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(shape.fill(.black))
        .clipShape(shape)
        .shadow(color: .black.opacity(expanded ? 0.45 : 0), radius: 14, y: 6)
        .offset(x: expanded ? 0 : model.collapsedOffsetX)
        .animation(.spring(response: 0.24, dampingFraction: 0.62), value: model.leftEarWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Collapsed

private struct CollapsedView: View {
    let model: NotchModel
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 0) {
            // Not clipped, so the artwork can travel outside the ear while it morphs.
            MediaEar(nowPlaying: model.nowPlaying, size: model.notchSize.height - 12, namespace: namespace)
                .frame(width: model.leftEarWidth)
                .opacity(model.nowPlaying.isPlaying ? 1 : 0)
            Color.clear.frame(width: model.notchSize.width)
            VolumeIcon(audio: model.audio)
                .font(.system(size: 13, weight: .medium))
                .frame(width: model.rightEarWidth)
        }
        .frame(height: model.notchSize.height)
    }
}

private struct MediaEar: View {
    let nowPlaying: NowPlayingController
    let size: CGFloat
    let namespace: Namespace.ID

    var body: some View {
        Group {
            if let artwork = nowPlaying.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(nowPlaying.accentColor)
                    .symbolEffect(.variableColor.iterative, isActive: nowPlaying.isPlaying)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .clipShape(ArtworkShape())
        // Only pair with the expanded artwork while the ear is showing; otherwise the big
        // artwork would grow out of a zero-width ear.
        .matchedGeometryEffect(id: nowPlaying.isPlaying ? ArtworkMorph.id : ArtworkMorph.hiddenID, in: namespace)
        .frame(width: size, height: size)
    }
}

/// Ids for the artwork that morphs between the left ear and the expanded panel.
private enum ArtworkMorph {
    static let id = "artwork"
    static let hiddenID = "artwork.hidden"
}

/// Rounded square whose corner radius follows its size, so the corners stay in
/// proportion while the artwork morphs (5pt in the ear, 12pt expanded).
private struct ArtworkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(max(rect.width * 0.12, 5), 12)
        return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
    }
}

/// Speaker icon that tracks the volume for built-in speakers, or the device's own icon
/// (AirPods, AirPlay, display...) otherwise.
private struct VolumeIcon: View {
    let audio: AudioController

    var body: some View {
        if audio.isMuted {
            Image(systemName: "speaker.slash.fill")
        } else if let device = audio.currentDevice, !device.isBuiltInSpeaker {
            Image(systemName: device.symbolName)
        } else {
            Image(systemName: "speaker.wave.3.fill", variableValue: audio.volume)
        }
    }
}

// MARK: - Expanded

private struct ExpandedView: View {
    let model: NotchModel
    let namespace: Namespace.ID

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: model.notchSize.height)
            HStack(alignment: .top, spacing: 16) {
                MediaSection(nowPlaying: model.nowPlaying, namespace: namespace)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                Rectangle()
                    .fill(.white.opacity(0.1))
                    .frame(width: 1)
                AudioSection(audio: model.audio)
                    .frame(width: 190)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 18)
            .frame(height: NotchModel.expandedBodyHeight)
        }
        .background(alignment: .topLeading) {
            // Faint glow tinted with the album art.
            if model.nowPlaying.artwork != nil {
                RadialGradient(colors: [model.nowPlaying.accentColor.opacity(0.22), .clear],
                               center: .topLeading, startRadius: 0, endRadius: 320)
            }
        }
    }

    /// Only the outer edges are usable; the middle sits behind the notch.
    private var header: some View {
        let side = max((NotchModel.expandedWidth - model.notchSize.width) / 2, 0)
        return HStack(spacing: 0) {
            HStack(spacing: 6) {
                if let app = SourceApp(bundleIdentifier: model.nowPlaying.info?.bundleIdentifier) {
                    Image(nsImage: app.icon).resizable().frame(width: 16, height: 16)
                    Text(app.name).lineLimit(1)
                }
            }
            .padding(.leading, 18)
            .padding(.trailing, 10)
            .frame(width: side, alignment: .leading)

            Spacer(minLength: 0)

            HStack {
                if let device = model.audio.currentDevice {
                    Text(device.name).lineLimit(1)
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 18)
            .frame(width: side, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.white.opacity(0.55))
    }
}

private struct SourceApp {
    let name: String
    let icon: NSImage

    init?(bundleIdentifier: String?) {
        guard let bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return nil }
        name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        icon = NSWorkspace.shared.icon(forFile: url.path)
    }
}

// MARK: Media

private struct MediaSection: View {
    let nowPlaying: NowPlayingController
    let namespace: Namespace.ID

    var body: some View {
        if let info = nowPlaying.info {
            HStack(spacing: 14) {
                artwork
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipShape(ArtworkShape())
                    .matchedGeometryEffect(id: ArtworkMorph.id, in: namespace)
                    .frame(width: 100, height: 100)
                    .onTapGesture { nowPlaying.openSourceApp() }
                    .help("Open the app that's playing")

                VStack(alignment: .leading, spacing: 2) {
                    Text(info.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(info.artist.isEmpty ? info.album : info.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Scrubber(info: info, accent: nowPlaying.accentColor) { nowPlaying.seek(to: $0) }
                    controls(isPlaying: info.isPlaying)
                }
            }
        } else {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(0.08))
                    .frame(width: 100, height: 100)
                    .overlay(Image(systemName: "music.note").font(.system(size: 30)).foregroundStyle(.white.opacity(0.35)))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nothing playing").font(.system(size: 14, weight: .semibold))
                    Text(nowPlaying.adapterError ?? "Play something in any app.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder private var artwork: some View {
        if let image = nowPlaying.artwork {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
        } else {
            Rectangle().fill(.white.opacity(0.08))
                .overlay(Image(systemName: "music.note").font(.system(size: 30)).foregroundStyle(.white.opacity(0.35)))
        }
    }

    private func controls(isPlaying: Bool) -> some View {
        HStack(spacing: 18) {
            Button { nowPlaying.previous() } label: {
                Image(systemName: "backward.fill").font(.system(size: 15))
            }
            Button { nowPlaying.togglePlayPause() } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 26)
            }
            Button { nowPlaying.next() } label: {
                Image(systemName: "forward.fill").font(.system(size: 15))
            }
        }
        .buttonStyle(NotchButtonStyle())
        .frame(maxWidth: .infinity)
    }
}

private struct Scrubber: View {
    let info: NowPlayingInfo
    let accent: Color
    let onSeek: (Double) -> Void

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.5, paused: !info.isPlaying)) { context in
            let elapsed = info.elapsed(at: context.date)
            VStack(spacing: 1) {
                BarSlider(value: info.duration > 0 ? elapsed / info.duration : 0, tint: accent,
                          isEnabled: info.duration > 0) { _ in } onEnd: { onSeek($0 * info.duration) }
                HStack {
                    Text(Self.format(elapsed))
                    Spacer()
                    Text("-" + Self.format(max(info.duration - elapsed, 0)))
                }
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    static func format(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.down))
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: Audio

private struct AudioSection: View {
    let audio: AudioController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button { audio.toggleMute() } label: {
                    Image(systemName: audio.isMuted ? "speaker.slash.fill" : "speaker.wave.3.fill",
                          variableValue: audio.volume)
                        .font(.system(size: 12))
                        .frame(width: 18)
                }
                .buttonStyle(NotchButtonStyle(padding: 4))
                .disabled(!audio.hasMuteControl)

                BarSlider(value: audio.isMuted ? 0 : audio.volume, tint: .white,
                          isEnabled: audio.hasVolumeControl) { audio.setVolume($0) }
            }
            .help(audio.hasVolumeControl ? "" : "This device has no software volume control")

            Text("OUTPUT")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.leading, 6)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 1) {
                    ForEach(audio.devices) { device in
                        DeviceRow(device: device, isCurrent: device.id == audio.currentDevice?.id) {
                            audio.setDefaultDevice(device)
                        }
                    }
                }
            }
        }
    }
}

private struct DeviceRow: View {
    let device: AudioDevice
    let isCurrent: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: device.symbolName)
                    .font(.system(size: 11))
                    .frame(width: 16)
                Text(device.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isCurrent {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                }
            }
            .foregroundStyle(.white.opacity(isCurrent ? 1 : 0.7))
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(hovering ? 0.1 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Controls

/// Thin capsule slider that thickens on hover. `onChange` fires while dragging,
/// `onEnd` once on release.
struct BarSlider: View {
    let value: Double
    var tint: Color = .white
    var isEnabled = true
    var onChange: (Double) -> Void
    var onEnd: ((Double) -> Void)? = nil

    @State private var dragValue: Double?
    @State private var hovering = false

    var body: some View {
        GeometryReader { geo in
            let v = min(max(dragValue ?? value, 0), 1)
            let active = isEnabled && (hovering || dragValue != nil)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                Capsule().fill(tint).frame(width: geo.size.width * v)
            }
            .frame(height: active ? 7 : 4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        guard isEnabled else { return }
                        let nv = min(max(g.location.x / geo.size.width, 0), 1)
                        dragValue = nv
                        onChange(nv)
                    }
                    .onEnded { g in
                        guard isEnabled else { return }
                        let nv = min(max(g.location.x / geo.size.width, 0), 1)
                        onEnd?(nv)
                        dragValue = nil
                    }
            )
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: active)
        }
        .frame(height: 14)
        .opacity(isEnabled ? 1 : 0.35)
    }
}

struct NotchButtonStyle: ButtonStyle {
    var padding: CGFloat = 6

    func makeBody(configuration: Configuration) -> some View {
        HoverButton(configuration: configuration, padding: padding)
    }

    private struct HoverButton: View {
        let configuration: Configuration
        let padding: CGFloat
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .padding(padding)
                .background(Circle().fill(.white.opacity(hovering && isEnabled ? 0.12 : 0)))
                .scaleEffect(configuration.isPressed ? 0.88 : 1)
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Circle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}
