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

    // Match Boring Notch physics (extracted)
    private var animationSpring: Animation { boringInteractiveSpring }
    private var openAnimation: Animation { boringOpenAnimation }
    private var closeAnimation: Animation { boringCloseAnimation }

    // Calculated values based on settings
    private var currentCornerRadius: CGFloat {
        let base: CGFloat = isExpanded ? 24 : 16
        return base * settings.get(SettingsDefaults.cornerRadiusScaling)
    }

    private var currentCompactHeight: CGFloat {
        return settings.get(SettingsDefaults.nonNotchHeight)
    }

    var body: some View {
        ZStack(alignment: .top) {
            // THE UNIFIED CAPSULE (The Mother Hull)
            VStack(spacing: 0) {
                if isExpanded {
                    ExpandedIslandRegion(animation: islandAnimation)
                        .transition(
                            .scale(scale: 0.8, anchor: .top)
                                .combined(with: .opacity)
                                .animation(.smooth(duration: 0.35))
                        )
                } else {
                    CompactIslandRegion(animation: islandAnimation)
                        .frame(height: currentCompactHeight)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(openAnimation) {
                                appState.activateOverlay(reason: .userExpanded)
                            }
                        }
                        .transition(.opacity)
                }
            }
            // 🎨 UPDATED VISUALS: Pure Black base + Customizable Core
            .background {
                ZStack {
                    appState.islandBackgroundColor
                    if settings.get(SettingsDefaults.enableBlur) {
                        VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: currentCornerRadius, style: .continuous))
            .compositingGroup()

            // EDGE + SHADOW (Boring Notch feel)
            .overlay(
                RoundedRectangle(cornerRadius: currentCornerRadius, style: .continuous)
                    .stroke(
                        Color.white.opacity((isExpanded || isHovering) ? 0.18 : 0.12),
                        lineWidth: (isExpanded || isHovering) ? 1 : 0.5
                    )
            )
            // ✅ 完全移除阴影以消除黑色像素残留
            // SwiftUI 的 shadow 在边缘可能会产生黑色像素伪影，特别是在高分辨率屏幕上
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            handleHover(hovering)
        }
        .animation(isExpanded ? openAnimation : closeAnimation, value: isExpanded)
        .ignoresSafeArea()
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
            return
        }

        if hovering {
            withAnimation(reduceMotion ? nil : animationSpring) {
                isHovering = true
            }

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

                withAnimation(openAnimation) {
                    appState.activateOverlay(reason: .userExpanded)
                }
            }
        } else {
            hoverTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }

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
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject private var settings = SettingsDefaults.shared

    let animation: Namespace.ID

    private var shouldShowMusicLiveActivity: Bool {
        settings.get(SettingsDefaults.showMusicLiveActivity) && !musicManager.isPlayerIdle
    }

    var body: some View {
        HStack(spacing: 8) {
            if shouldShowMusicLiveActivity {
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
                ForEach(AppState.IslandSection.allCases, id: \.self) { section in
                    tabItem(for: section)
                }
                
                Spacer()
                
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
                    case .calendar:
                        CalendarView()
                    case .zone3:
                        Zone3ContentView(onClose: { appState.deactivateOverlay() })
                    }
                }
            }
            .frame(height: 250) // Increased from 190 to fit Calendar view
        }
    }
    
    private func tabItem(for section: AppState.IslandSection) -> some View {
        let isSelected = appState.currentSection == section
        let isHovered = hoveredSection == section
        
        return HStack(spacing: 6) {
            Image(systemName: section.iconName)
                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
            
            if isSelected {
                Text(section.displayName)
                    .font(.system(size: 11, weight: .bold))
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
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
