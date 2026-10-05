import SwiftUI

// MARK: - NotchHomeView (The Holy Capsule Host)
struct NotchHomeView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var settings = SettingsDefaults.shared
    @Namespace var islandAnimation

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering: Bool = false
    @State private var hoverTask: Task<Void, Never>? = nil

    private var isExpanded: Bool { appState.islandMode == .expanded }
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

    /// The size IslandController gives the panel, so the settled island fills it exactly
    private var islandSize: CGSize {
        NotchMetrics.islandSize(
            expanded: isExpanded,
            section: appState.currentSection,
            notch: notch,
            wings: appState.liveActivityWings,
            largeDisplay: appState.isOnLargeDisplay,
            nonNotchHeight: settings.get(SettingsDefaults.nonNotchHeight)
        )
    }

    var body: some View {
        island
            // Fixed-size canvas: the island hangs from its top center and the panel crops it,
            // so resizing the panel never moves or re-lays out the island
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
            .background(SwipeMonitor { handleSwipe($0) })
    }

    /// A two-finger swipe down opens the island, one up closes it
    private func handleSwipe(_ direction: SwipeDirection) {
        guard settings.get(SettingsDefaults.enableGestures) else { return }
        switch direction {
        case .down where !isExpanded:
            openIsland()
        case .up where isExpanded && !appState.isDraggingOver:
            hoverTask?.cancel()
            appState.isPeekingNotch = false
            withAnimation(closeAnimation) {
                appState.deactivateIsland()
            }
        default:
            break
        }
    }

    private var island: some View {
        // THE UNIFIED CAPSULE (The Mother Hull)
        ZStack(alignment: .top) {
            if isExpanded {
                ExpandedIslandRegion(animation: islandAnimation, notch: notch)
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
        // Black at least as far down as the camera housing: the island has to be exactly as black as the notch
        // it grows out of. Only the Glass theme lets the glass through below it
        .background(IslandBackground(
            theme: appState.islandTheme,
            color: appState.islandBackgroundColor,
            solidHeight: notch.height > 0 ? notch.height : settings.get(SettingsDefaults.nonNotchHeight)
        ))
        .clipShape(NotchShape(topCornerRadius: topCornerRadius, bottomCornerRadius: bottomCornerRadius))
        .compositingGroup()
        // Liquid Glass under the Glass theme: the island's body, without the top flares, which stay black.
        // Outside the compositing group, which would render it offscreen where it can't sample the screen.
        // Only while open: the collapsed island is all camera housing and stays as black as the notch
        .background(alignment: .top) {
            if appState.islandTheme == .glass {
                IslandGlass(cornerRadius: bottomCornerRadius)
                    .frame(width: max(0, islandSize.width - 2 * topCornerRadius), height: islandSize.height)
                    .opacity(isExpanded ? 1 : 0)
                    .allowsHitTesting(false)
            }
        }
        // No outline: a stroke would trace the notch and give the island away
        // ✅ Shadow removed entirely to avoid leftover black pixels
        // SwiftUI's shadow can leave black pixel artifacts at the edges, especially on high-resolution displays
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

    /// Opens the island; when a high-priority plugin (an agent at work) shows beside the notch, on its tab
    private func openIsland() {
        if appState.showsLiveActivity, appState.liveActivity == .priorityPlugin, let plugin = PluginStore.shared.priorityPlugin {
            let tab = IslandTab.tab(forPlugin: plugin.manifest.id)
            if TabStore.shared.isEnabled(tab) { appState.currentSection = tab }
        }
        withAnimation(openAnimation) {
            appState.activateIsland(reason: .userExpanded)
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
                // Not while you're typing in it (an answer to an agent, a note): what you wrote would be lost.
                // It closes once you're done, e.g. you've sent it or clicked another app
                while !Task.isCancelled, appState.isTyping {
                    try? await Task.sleep(for: .milliseconds(300))
                }
                guard !Task.isCancelled, isExpanded, !appState.isDraggingOver else { return }
                // Ignore a stray exit event while the pointer is still over the island
                guard !appState.islandFrame.contains(NSEvent.mouseLocation) else { return }
                appState.isPeekingNotch = false
                withAnimation(closeAnimation) {
                    appState.deactivateIsland()
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
                guard appState.islandMode == .compact else { return }

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
