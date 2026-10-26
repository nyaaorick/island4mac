import SwiftUI

struct ExpandedIslandRegion: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var tabs = TabStore.shared
    var animation: Namespace.ID
    /// Camera housing. With a notch the tabs sit either side of it, level with the camera, and the content
    /// starts right below it; without one they get their own tab bar
    var notch: CGSize

    @State private var hoveredSection: IslandTab? = nil

    var body: some View {
        VStack(spacing: 0) {
            if notch == .zero {
                tabBar
                Divider().background(Color.white.opacity(0.1))
            } else {
                cameraRow
            }
            content
        }
    }

    /// Your tabs, the first half left of the camera and the rest right of it, each group centered on its side.
    /// No close button up here: the island closes when the pointer leaves it, on a swipe up or with ⇧⌘Space
    private var cameraRow: some View {
        let sections = tabs.enabledTabs[...]
        let leading = (sections.count + 1) / 2
        let groups = [sections.prefix(leading), sections.dropFirst(leading)]
        // Only the built-in display has a camera housing, and it never gets the large layout
        let side = (NotchMetrics.expandedWidth - 2 * NotchMetrics.expandedTopRadius - notch.width) / 2 - 2 * Self.tabGroupMargin
        let layout = TabBarLayout.fitting(groups.map { $0.map(\.displayName) }, in: side)
        return HStack(spacing: 0) {
            tabGroup(groups[0], layout: layout)
                .padding(.horizontal, Self.tabGroupMargin)
            Color.clear
                .frame(width: notch.width)
            tabGroup(groups[1], layout: layout)
                .padding(.horizontal, Self.tabGroupMargin)
        }
        .frame(height: notch.height)
    }

    /// Air between a group of tabs and the island's edge or the camera
    private static let tabGroupMargin: CGFloat = 8
    /// What the tab bar keeps for its padding, the settings and close buttons and the gaps between them
    private static let tabBarControlsWidth: CGFloat = 28 + 12 + 28 + 12 + 32 + 8

    private func tabGroup(_ sections: ArraySlice<IslandTab>, layout: TabBarLayout) -> some View {
        Group {
            if layout.scrolls {
                ScrollView(.horizontal) { tabRow(sections, layout: layout) }
                    .scrollIndicators(.never)
            } else {
                tabRow(sections, layout: layout)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func tabRow(_ sections: ArraySlice<IslandTab>, layout: TabBarLayout) -> some View {
        HStack(spacing: layout.itemSpacing) {
            ForEach(sections, id: \.self) { section in
                tabItem(for: section, layout: layout)
            }
        }
    }

    /// Tabs row on a display without a notch, with the close button and the Agents tab's controls
    private var tabBar: some View {
        let width = (appState.isOnLargeDisplay ? NotchMetrics.largeDisplayExpandedWidth : NotchMetrics.expandedWidth)
            - 2 * NotchMetrics.expandedTopRadius
        let layout = TabBarLayout.fitting([tabs.enabledTabs.map(\.displayName)], in: width - Self.tabBarControlsWidth)
        return HStack(spacing: 12) {
            if layout.scrolls {
                tabGroup(tabs.enabledTabs[...], layout: layout)
            } else {
                tabRow(tabs.enabledTabs[...], layout: layout)
                Spacer()
            }

            PluginSettingsButton(tab: appState.currentSection)
            
            // Close Button - Using custom view to ensure clickability
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 18))
                .foregroundColor(.white.opacity(0.3))
                .frame(width: 32, height: 32)
                .contentShape(Circle())
                .onHover { h in if h { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() } }
                .onTapGesture {
                    withAnimation(boringInteractiveSpring) {
                        appState.deactivateIsland()
                    }
                }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(height: NotchMetrics.tabBarHeight - 1)
    }

    private var content: some View {
        ZStack {
            // Invisible background to capture events in the whole content area
            Color.black.opacity(0.001)

            Group {
                switch appState.currentSection {
                case .music:
                    // The island's player, for whatever plays: the Music plugin's track, or another plugin's
                    ExpandedMusicView(musicStore: NowPlayingStore.shared, animation: animation)
                case .clipboard, .files, .agents:
                    // Drawn by the plugins that ship in the app
                    PluginTabView(pluginID: IslandTab.builtInTabsOfPlugins.first { $0.value == appState.currentSection }?.key ?? "")
                        .id(appState.currentSection)
                default:
                    PluginTabView(pluginID: appState.currentSection.pluginID ?? "")
                        // A fresh view per plugin, so switching between two plugin tabs tells both
                        .id(appState.currentSection)
                }
            }
            // Files, and plugins that take drops: shows where to drop and hands the drop over
            .islandDropZone(for: appState.currentSection)
        }
        // The rest of the open island, sized per tab by NotchMetrics.expandedSize(for:largeDisplay:notch:)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // With the tabs beside the camera there's no tab bar, so a plugin's settings button floats in its corner
        .overlay(alignment: .bottomTrailing) {
            if notch != .zero {
                PluginSettingsButton(tab: appState.currentSection)
                    .padding(6)
            }
        }
    }

    private func tabItem(for section: IslandTab, layout: TabBarLayout) -> some View {
        let isSelected = appState.currentSection == section
        let isHovered = hoveredSection == section
        
        // Every tab keeps its label and weight, so selecting one never resizes the tabs or pushes them around
        // Labels always show whole (TabBarLayout leaves them the room), never cut short or shrunk
        return HStack(spacing: layout.iconSpacing) {
            if layout.showsIcons {
                Image(systemName: section.iconName)
                    .font(.system(size: TabBarLayout.fontSize, weight: .semibold))
                    .frame(width: TabBarLayout.iconWidth)
            }
            Text(section.displayName)
                .font(.system(size: TabBarLayout.fontSize, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, layout.horizontalPadding)
        .background {
            if isSelected {
                IslandSurface(level: .tile, cornerRadius: 999, isHighlighted: isHovered)
            } else if isHovered {
                IslandSurface(level: .inset, cornerRadius: 999)
            }
        }
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
