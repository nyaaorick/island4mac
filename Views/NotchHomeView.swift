import SwiftUI

// MARK: - NotchHomeView (The Holy Capsule Host)
struct NotchHomeView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var settings = SettingsDefaults.shared
    @Namespace var islandAnimation

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering: Bool = false
    @State private var hoverTask: Task<Void, Never>? = nil

    private var isExpanded: Bool { appState.overlayMode == .expanded }
    private var notch: CGSize { appState.notchSize }

    // Match Boring Notch physics (extracted)
    private var animationSpring: Animation { boringInteractiveSpring }
    private var openAnimation: Animation { boringOpenAnimation }
    private var closeAnimation: Animation { boringCloseAnimation }

    // Notch outline: the top corners flare into the menu bar like the notch itself
    private var topCornerRadius: CGFloat {
        isExpanded ? NotchMetrics.expandedTopRadius : NotchMetrics.compactTopRadius
    }

    // Calculated values based on settings
    private var bottomCornerRadius: CGFloat {
        let base: CGFloat = isExpanded ? 24 : 14
        return base * settings.get(SettingsDefaults.cornerRadiusScaling)
    }

    /// Collapsed content sits left of the notch only, so the island's center moves left with it
    private var islandOffset: CGFloat {
        NotchMetrics.islandOffset(expanded: isExpanded, notch: notch, wings: appState.liveActivityWings)
    }

    /// The size OverlayWindowController gives the panel, so the settled island fills it exactly
    private var islandSize: CGSize {
        NotchMetrics.islandSize(
            expanded: isExpanded,
            section: appState.currentSection,
            notch: notch,
            wings: appState.liveActivityWings,
            nonNotchHeight: settings.get(SettingsDefaults.nonNotchHeight)
        )
    }

    var body: some View {
        island
            // Fixed-size canvas: the island hangs from its top center and the panel crops it,
            // so resizing the panel never moves or re-lays out the island
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
    }

    private var island: some View {
        // THE UNIFIED CAPSULE (The Mother Hull)
        ZStack(alignment: .top) {
            if isExpanded {
                ExpandedIslandRegion(animation: islandAnimation)
                    // Start the content below the camera housing
                    .padding(.top, notch.height)
                    // Lay out at the final size so nothing reflows while the island grows around it
                    .frame(
                        width: islandSize.width - 2 * NotchMetrics.expandedTopRadius,
                        height: islandSize.height,
                        alignment: .top
                    )
                    // Fade in once the island has started opening; fade out before it shrinks
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
                            .animation(.easeOut(duration: 0.25).delay(0.05)),
                        removal: .opacity.animation(.easeIn(duration: 0.12))
                    ))
            } else {
                CompactIslandRegion(animation: islandAnimation)
                    .frame(width: max(0, islandSize.width - 2 * NotchMetrics.compactTopRadius), height: islandSize.height)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        openIsland()
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: 0.2).delay(0.15)),
                        removal: .opacity.animation(.easeIn(duration: 0.1))
                    ))
            }
        }
        .frame(width: islandSize.width, height: islandSize.height, alignment: .top)
        // 🎨 UPDATED VISUALS: Pure Black base + Customizable Core
        .background {
            ZStack {
                appState.islandBackgroundColor
                // Collapsed, the island has to be as dark as the notch it hides in, so the blur fades with it
                if settings.get(SettingsDefaults.enableBlur) {
                    VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                        .opacity(isExpanded ? 1 : 0)
                }
            }
        }
        .clipShape(NotchShape(topCornerRadius: topCornerRadius, bottomCornerRadius: bottomCornerRadius))
        .compositingGroup()
        // No outline: a stroke would trace the notch and give the island away
        // ✅ 完全移除阴影以消除黑色像素残留
        // SwiftUI 的 shadow 在边缘可能会产生黑色像素伪影，特别是在高分辨率屏幕上
        .contentShape(Rectangle())
        .onHover { hovering in
            handleHover(hovering)
        }
        .offset(x: islandOffset)
        .animation(isExpanded ? openAnimation : closeAnimation, value: isExpanded)
        // Each tab has its own open size
        .animation(reduceMotion ? nil : animationSpring, value: appState.currentSection)
        .animation(reduceMotion ? nil : animationSpring, value: appState.liveActivityWings)
    }

    /// Opens the island; when an agent session is showing beside the notch, on the Agents tab
    private func openIsland() {
        if appState.showsLiveActivity && AgentSessionStore.shared.showsCompactLiveActivity {
            appState.currentSection = .agents
        }
        withAnimation(openAnimation) {
            appState.activateOverlay(reason: .userExpanded)
        }
    }

    private func handleHover(_ hovering: Bool) {
        hoverTask?.cancel()

        // Only apply magnetic hover feel when compact.
        if isExpanded {
            if isHovering {
                withAnimation(reduceMotion ? nil : animationSpring) {
                    isHovering = false
                }
            }
            // Collapse shortly after the pointer leaves the open island (not while files are dragged in)
            guard !hovering, !appState.isDraggingOver else { return }
            hoverTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled, isExpanded, !appState.isDraggingOver else { return }
                // Ignore a stray exit event while the pointer is still over the island
                guard !appState.islandFrame.contains(NSEvent.mouseLocation) else { return }
                appState.isPeekingNotch = false
                withAnimation(closeAnimation) {
                    appState.deactivateOverlay()
                }
            }
            return
        }

        if hovering {
            withAnimation(reduceMotion ? nil : animationSpring) {
                isHovering = true
            }
            // Paused music shows beside the notch while the pointer is on it
            appState.isPeekingNotch = true

            if settings.get(SettingsDefaults.enableHaptics) {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }

            guard settings.get(SettingsDefaults.openNotchOnHover) else { return }
            let delay = settings.get(SettingsDefaults.minimumHoverDuration)
            let nanos = UInt64(max(0, delay) * 1_000_000_000)

            hoverTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: nanos)
                guard !Task.isCancelled else { return }
                guard isHovering else { return }
                guard appState.overlayMode == .compact else { return }

                openIsland()
            }
        } else {
            hoverTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }

                appState.isPeekingNotch = false
                withAnimation(reduceMotion ? nil : animationSpring) {
                    isHovering = false
                }
            }
        }
    }
}

// MARK: - Compact Region
struct CompactIslandRegion: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var agents = AgentSessionStore.shared

    let animation: Namespace.ID

    /// An agent session takes the wings over from music while it works, waits for you or has just finished
    private var agentSession: AgentSession? {
        agents.showsCompactLiveActivity ? agents.liveSession : nil
    }

    var body: some View {
        let notch = appState.notchSize
        if notch == .zero {
            // No notch on this display: a small pill at the top center
            HStack(spacing: 8) {
                if appState.showsLiveActivity, let session = agentSession {
                    CompactAgentLiveActivityView(session: session)
                } else if appState.showsLiveActivity && MusicManager.shared.showsCompactLiveActivity {
                    CompactMusicLiveActivityView(animation: animation)
                } else {
                    AnimatedFaceView()
                        .frame(width: 28, height: 14)
                    Spacer()
                    Image(systemName: appState.currentSection.iconName)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.3))
                }
            }
            .padding(.horizontal, 14)
        } else if appState.showsLiveActivity, let session = agentSession {
            AgentNotchLiveActivityView(session: session, notch: notch, wings: appState.liveActivityWings, activeCount: agents.activeSessionCount)
        } else if appState.showsLiveActivity && MusicManager.shared.showsCompactLiveActivity {
            NotchLiveActivityView(notch: notch, wings: appState.liveActivityWings, animation: animation)
        } else {
            // Nothing playing: stay hidden inside the notch
            Color.clear
        }
    }
}

// MARK: - Notch Live Activity (Album Art | Notch | Spectrum)

/// Collapsed content around the notch: the primary item in the left wing and the secondary one in the right.
/// With room on one side only, the primary item goes there, and the secondary one beside it if the left has room for both.
struct NotchWingsLayout<Primary: View, Secondary: View>: View {
    let notch: CGSize
    let wings: IslandWings
    /// Content of a wing, given the wing's width
    @ViewBuilder let primary: (_ width: CGFloat) -> Primary
    @ViewBuilder let secondary: (_ width: CGFloat) -> Secondary

    var body: some View {
        HStack(spacing: 0) {
            if wings.trailing == 0, wings.leading >= 2 * NotchMetrics.minWingWidth {
                let half = wings.leading / 2
                primary(half).frame(width: half)
                secondary(half).frame(width: half)
            } else if wings.leading > 0 {
                primary(wings.leading).frame(width: wings.leading)
            }

            // Hidden behind the camera housing
            Color.clear
                .frame(width: notch.width)

            if wings.trailing > 0 {
                Group {
                    if wings.leading > 0 { secondary(wings.trailing) } else { primary(wings.trailing) }
                }
                .frame(width: wings.trailing)
            }
        }
    }
}

/// Collapsed now-playing on a notched display: album art and spectrum beside the notch
private struct NotchLiveActivityView: View {
    @ObservedObject private var musicManager = MusicManager.shared
    @ObservedObject private var settings = SettingsDefaults.shared

    let notch: CGSize
    let wings: IslandWings
    let animation: Namespace.ID

    private var accent: Color {
        if settings.get(SettingsDefaults.playerColorTinting) {
            return Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.55)
        }
        return .accentColor
    }

    var body: some View {
        NotchWingsLayout(notch: notch, wings: wings) { width in
            // A narrow wing keeps a little air around the artwork
            let artSize = min(max(16, notch.height - 12), width - 2)
            Image(nsImage: musicManager.albumArt)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .matchedGeometryEffect(id: "album_art", in: animation)
                .frame(width: artSize, height: artSize)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } secondary: { _ in
            spectrum
        }
    }

    @ViewBuilder
    private var spectrum: some View {
        if settings.get(SettingsDefaults.useMusicVisualizer) {
            Rectangle()
                .fill((settings.get(SettingsDefaults.playerColorTinting) ? accent : .white).opacity(0.85))
                .frame(width: 18, height: 12)
                .matchedGeometryEffect(id: "spectrum", in: animation)
                .mask {
                    AudioSpectrumView(isPlaying: $musicManager.isPlaying)
                        .frame(width: 16, height: 12)
                }
                .accessibilityHidden(true)
        } else {
            Image(systemName: "waveform")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(musicManager.isPlaying ? .green : Color.white.opacity(0.35))
                .symbolEffect(.bounce, options: .repeating, value: musicManager.isPlaying)
        }
    }
}

// MARK: - Compact Music Live Activity (Album Art + Progress + Lyrics)

private struct CompactMusicLiveActivityView: View {
    @ObservedObject private var musicManager = MusicManager.shared
    @ObservedObject private var settings = SettingsDefaults.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let animation: Namespace.ID

    private var accent: Color {
        if settings.get(SettingsDefaults.playerColorTinting) {
            return Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.55)
        }
        return .accentColor
    }

    var body: some View {
        GeometryReader { geo in
            let marqueeWidth = max(80, geo.size.width - 24 - 10 - 8 - 8)

            HStack(spacing: 8) {
                // Album art (tiny)
                Image(nsImage: musicManager.albumArt)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .matchedGeometryEffect(id: "album_art", in: animation)
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    // Song title
                    IslandMarqueeText(
                        text: .constant(musicManager.songTitle.isEmpty ? "Not Playing" : musicManager.songTitle),
                        font: .system(size: 11, weight: .semibold),
                        nsFont: .systemFont(ofSize: 11, weight: .semibold),
                        textColor: .white,
                        frameWidth: marqueeWidth
                    )

                    // Lyrics (real-time) or artist line
                    if settings.get(SettingsDefaults.enableLyrics) {
                        TimelineView(.animation(minimumInterval: 0.25)) { timeline in
                            let elapsed = musicManager.estimatedPlaybackPosition(at: timeline.date)
                            let line = compactLyricsLine(elapsed: elapsed)

                            IslandMarqueeText(
                                text: .constant(line),
                                font: .system(size: 10, weight: .medium),
                                nsFont: .systemFont(ofSize: 10, weight: .medium),
                                textColor: musicManager.isFetchingLyrics ? Color.white.opacity(0.35) : Color.white.opacity(0.65),
                                frameWidth: marqueeWidth
                            )
                            .id(line)
                        }
                    } else {
                        IslandMarqueeText(
                            text: .constant(musicManager.artistName.isEmpty ? "" : musicManager.artistName),
                            font: .system(size: 10, weight: .medium),
                            nsFont: .systemFont(ofSize: 10, weight: .medium),
                            textColor: Color.white.opacity(0.55),
                            frameWidth: marqueeWidth
                        )
                    }
                }

                Spacer(minLength: 0)

                if settings.get(SettingsDefaults.useMusicVisualizer) {
                    // ✅ 移除 .gradient 光效，只使用纯色填充
                    Rectangle()
                        .fill((settings.get(SettingsDefaults.playerColorTinting) ? accent : .white).opacity(0.85))
                        .frame(width: 18, height: 12)
                        .matchedGeometryEffect(id: "spectrum", in: animation)
                        .mask {
                            AudioSpectrumView(isPlaying: $musicManager.isPlaying)
                                .frame(width: 16, height: 12)
                        }
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "waveform")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(musicManager.isPlaying ? .green : Color.white.opacity(0.35))
                        .symbolEffect(.bounce, options: .repeating, value: musicManager.isPlaying)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) {
                CompactMusicProgressBar(accent: accent)
                    .padding(.leading, 24 + 8) // align under text
                    .padding(.trailing, 2)
                    .padding(.bottom, 2)
            }
        }
        .frame(height: 28)
    }

    private func compactLyricsLine(elapsed: Double) -> String {
        if musicManager.isFetchingLyrics {
            return "Loading lyrics…"
        }

        if !musicManager.syncedLyrics.isEmpty {
            let line = musicManager.lyricLine(at: elapsed)
            return line.isEmpty ? "…" : line
        }

        let trimmed = musicManager.currentLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return musicManager.artistName.isEmpty ? "" : musicManager.artistName
        }

        // Compact: single line
        return trimmed.replacingOccurrences(of: "\n", with: " ")
    }
}

private struct CompactMusicProgressBar: View {
    @ObservedObject private var musicManager = MusicManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isSeeking = false
    @State private var seekTime: Double = 0

    let accent: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: musicManager.playbackRate > 0 ? 0.2 : nil)) { timeline in
            GeometryReader { geo in
                let duration = musicManager.songDuration
                let elapsed = isSeeking ? seekTime : musicManager.estimatedPlaybackPosition(at: timeline.date)
                let progress = duration > 0 ? min(1.0, max(0.0, elapsed / duration)) : 0

                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))

                    if duration > 0 {
                        Capsule()
                            .fill(accent.opacity(0.9))
                            .frame(width: geo.size.width * progress)
                            .animation(reduceMotion ? nil : .linear(duration: 0.2), value: progress)
                    } else if musicManager.isPlaying {
                        // Indeterminate shimmer when duration is unknown
                        let barWidth = max(12, geo.size.width * 0.35)
                        let period: TimeInterval = 1.3
                        let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
                        let x = reduceMotion ? 0 : (CGFloat(phase) * (geo.size.width + barWidth) - barWidth)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [accent.opacity(0.25), accent.opacity(0.85), accent.opacity(0.25)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: barWidth)
                            .offset(x: x)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    duration > 0
                    ? DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            let width = max(CGFloat(1), geo.size.width)
                            let pct = min(1.0, max(0.0, Double(gesture.location.x / width)))
                            seekTime = pct * duration
                            if !isSeeking { isSeeking = true }
                        }
                        .onEnded { _ in
                            let target = min(max(0, seekTime), duration)
                            isSeeking = false
                            musicManager.seek(to: target)
                        }
                    : nil
                )
                .animation(.spring(response: 0.25, dampingFraction: 0.85), value: isSeeking)
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Expanded Region
struct ExpandedIslandRegion: View {
    @EnvironmentObject var appState: AppState
    var animation: Namespace.ID
    
    @State private var hoveredSection: AppState.IslandSection? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // Header: Tabs
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    ForEach(AppState.IslandSection.allCases, id: \.self) { section in
                        tabItem(for: section)
                    }
                }

                Spacer()

                if appState.currentSection == .agents {
                    AgentTabControls()
                }
                
                // Close Button - Using custom view to ensure clickability
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.3))
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
                    .onHover { h in if h { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() } }
                    .onTapGesture {
                        withAnimation(boringInteractiveSpring) {
                            appState.deactivateOverlay()
                        }
                    }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .frame(height: NotchMetrics.tabBarHeight - 1)
            
            Divider().background(Color.white.opacity(0.1))
            
            // Content Anchor
            ZStack {
                // Invisible background to capture events in the whole content area
                Color.black.opacity(0.001)
                
                Group {
                    switch appState.currentSection {
                    case .music:
                        ExpandedMusicView(musicManager: MusicManager.shared, animation: animation)
                    case .clipboard:
                        ClipboardHubView(vault: appState.clipVault)
                    case .files:
                        ShelfView()
                    case .agents:
                        AgentsView()
                    }
                }
            }
            // The rest of the open island, sized per tab by NotchMetrics.expandedSize(for:)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    private func tabItem(for section: AppState.IslandSection) -> some View {
        let isSelected = appState.currentSection == section
        let isHovered = hoveredSection == section
        
        // Every tab keeps its label and weight, so selecting one never resizes the tabs or pushes them around
        return HStack(spacing: 6) {
            Image(systemName: section.iconName)
                .font(.system(size: 11, weight: .semibold))
            Text(section.displayName)
                .font(.system(size: 11, weight: .semibold))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            Capsule()
                .fill(isSelected ? Color.white.opacity(0.15) : (isHovered ? Color.white.opacity(0.08) : Color.clear))
        )
        .foregroundColor(isSelected ? .white : .white.opacity(0.6))
        .contentShape(Capsule())
        .onHover { h in
            hoveredSection = h ? section : nil
            if h { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .onTapGesture {
            withAnimation(boringInteractiveSpring) {
                appState.currentSection = section
            }
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }
}

// MARK: - Notch Shape

/// Island geometry shared with OverlayWindowController
enum NotchMetrics {
    /// Outward flare of the top corners, like the curve where the notch meets the top edge
    static let compactTopRadius: CGFloat = 6
    static let expandedTopRadius: CGFloat = 19

    /// Tabs row and divider at the top of the open island
    static let tabBarHeight: CGFloat = 53

    /// Width of the open island. The same for every tab, so switching tabs never slides the tab bar
    /// out from under the pointer
    static let expandedWidth: CGFloat = 640

    /// Open island below the camera housing: the tab bar plus a content area as tall as what each tab shows
    static func expandedSize(for section: AppState.IslandSection) -> CGSize {
        let contentHeight: CGFloat
        switch section {
        case .music:
            // Artwork beside title, lyrics, progress and controls
            contentHeight = 190
        case .clipboard:
            // One row of 160pt cards
            contentHeight = 210
        case .files:
            // Shelf header over a scrolling grid
            contentHeight = 260
        case .agents:
            // A couple of session rows with their task lists; the list scrolls
            contentHeight = 270
        }
        return CGSize(width: expandedWidth, height: tabBarHeight + contentHeight)
    }
    /// Collapsed pill on displays without a notch
    static let nonNotchWidth: CGFloat = 185
    /// Room around the open island so the open spring's overshoot isn't cut off by the panel
    static let overshootMargin: CGFloat = 10

    /// Widest a wing of collapsed content gets (artwork, spectrum, status, progress)
    static func wingWidth(for notch: CGSize) -> CGFloat {
        notch.height + 6
    }

    /// Narrowest wing worth showing: the artwork or the agent's status glyph, with a little air
    static let minWingWidth: CGFloat = 16
    /// Air kept between a wing and the nearest menu or status icon. Their frames already include padding,
    /// and the island's flared top corners only reach past its body above the icons
    static let wingMargin: CGFloat = 2

    /// Wings that fit into the room the menus and status icons leave beside the notch. The primary item
    /// (artwork, agent status) goes left and the secondary one (spectrum, progress) right; with no room on the
    /// right both go left, as they do while that room is unknown. Nothing is ever laid over a menu or an icon.
    static func liveActivityWings(leadingRoom: CGFloat?, trailingRoom: CGFloat?, notch: CGSize) -> IslandWings {
        let wing = wingWidth(for: notch)
        let left = (leadingRoom ?? .infinity) - wingMargin
        let right = (trailingRoom ?? 0) - wingMargin
        if right >= minWingWidth {
            let leading = left >= minWingWidth ? min(wing, left).rounded(.down) : 0
            return IslandWings(leading: leading, trailing: min(wing, right).rounded(.down))
        }
        if left >= 2 * wing { return IslandWings(leading: 2 * wing, trailing: 0) }
        return IslandWings(leading: left >= minWingWidth ? min(wing, left).rounded(.down) : 0, trailing: 0)
    }

    /// Horizontal offset of the island's center from the notch's, when its wings differ in width
    static func islandOffset(expanded: Bool, notch: CGSize, wings: IslandWings) -> CGFloat {
        guard !expanded, notch != .zero else { return 0 }
        return (wings.trailing - wings.leading) / 2
    }

    /// Settled size of the island; the panel matches it (plus `overshootMargin` when open)
    static func islandSize(expanded: Bool, section: AppState.IslandSection, notch: CGSize, wings: IslandWings, nonNotchHeight: CGFloat) -> CGSize {
        if expanded {
            // Content starts below the camera housing
            let open = expandedSize(for: section)
            return CGSize(width: open.width, height: open.height + notch.height)
        }
        // No notch (external display): a small pill at the top center
        guard notch != .zero else {
            return CGSize(width: nonNotchWidth, height: nonNotchHeight)
        }
        // Collapsed: the notch itself, plus the live activity beside it
        let width = notch.width + 2 * compactTopRadius + wings.leading + wings.trailing
        return CGSize(width: width, height: notch.height)
    }

    /// Fixed size of the SwiftUI canvas: the largest open island plus its overshoot margin
    static func canvasSize(notch: CGSize) -> CGSize {
        let openSizes = AppState.IslandSection.allCases.map { expandedSize(for: $0) }
        return CGSize(
            width: (openSizes.map(\.width).max() ?? 0) + 2 * overshootMargin,
            height: (openSizes.map(\.height).max() ?? 0) + notch.height + overshootMargin
        )
    }
}

/// Width of the collapsed island's content left and right of the notch
struct IslandWings: Equatable {
    var leading: CGFloat = 0
    var trailing: CGFloat = 0

    static let none = IslandWings()
    var isEmpty: Bool { leading == 0 && trailing == 0 }
}

/// Notch outline: flat top edge, outward-curving top corners and rounded bottom corners.
/// Adapted from boring.notch (originally DynamicNotchKit by MrKai77).
struct NotchShape: Shape {
    private var topCornerRadius: CGFloat
    private var bottomCornerRadius: CGFloat

    init(topCornerRadius: CGFloat, bottomCornerRadius: CGFloat) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let top = min(topCornerRadius, rect.width / 2, rect.height)
        // Keep the bottom corners inside the body for short or narrow islands
        let bottom = max(0, min(bottomCornerRadius, rect.height - top, (rect.width - 2 * top) / 2))

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top, y: rect.minY + top),
            control: CGPoint(x: rect.minX + top, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
            control: CGPoint(x: rect.minX + top, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
            control: CGPoint(x: rect.maxX - top, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - top, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}
