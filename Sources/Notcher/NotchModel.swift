import Observation
import SwiftUI

/// Shared state for the notch: geometry, expanded/collapsed, and the two data sources.
/// The window controller and the SwiftUI view both size things from here, so the
/// hover hit-rects always match what's drawn.
@Observable
@MainActor
final class NotchModel {
    let audio: AudioController
    let nowPlaying: NowPlayingController

    /// Size of the physical notch, from the screen's safe area.
    var notchSize = CGSize(width: 200, height: 32)
    private(set) var isExpanded = false

    // Collapsed pill
    static let collapsedTopRadius: CGFloat = 6
    static let collapsedBottomRadius: CGFloat = 10
    // Expanded panel
    static let expandedTopRadius: CGFloat = 12
    static let expandedBottomRadius: CGFloat = 24
    static let expandedBodyHeight: CGFloat = 150
    static let expandedWidth: CGFloat = 580

    init(audio: AudioController, nowPlaying: NowPlayingController) {
        self.audio = audio
        self.nowPlaying = nowPlaying
    }

    var earWidth: CGFloat { notchSize.height + 12 }
    /// The media ear shrinks away when nothing is playing.
    var leftEarWidth: CGFloat { nowPlaying.isPlaying ? earWidth : 0 }
    var rightEarWidth: CGFloat { earWidth }

    /// Size of the black shape, including the flared top corners on each side.
    var collapsedSize: CGSize {
        CGSize(width: leftEarWidth + notchSize.width + rightEarWidth + 2 * Self.collapsedTopRadius,
               height: notchSize.height)
    }

    var expandedSize: CGSize {
        CGSize(width: Self.expandedWidth + 2 * Self.expandedTopRadius,
               height: notchSize.height + Self.expandedBodyHeight)
    }

    /// Horizontal offset of the collapsed pill from the notch's center, so the notch
    /// itself stays centered when the ears are different widths.
    var collapsedOffsetX: CGFloat { (rightEarWidth - leftEarWidth) / 2 }

    /// The window is fixed at the expanded size plus room for the shadow.
    var windowSize: CGSize {
        CGSize(width: expandedSize.width + 60, height: expandedSize.height + 40)
    }

    func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded else { return }
        withAnimation(.spring(response: 0.24, dampingFraction: expanded ? 0.62 : 0.9)) {
            isExpanded = expanded
        }
    }
}
