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
        return HStack(spacing: 0) {
            tabGroup(sections.prefix(leading))
            Color.clear
                .frame(width: notch.width)
            tabGroup(sections.dropFirst(leading))
        }
        .frame(height: notch.height)
    }

    private func tabGroup(_ sections: ArraySlice<IslandTab>) -> some View {
        HStack(spacing: 4) {
            ForEach(sections, id: \.self) { section in
                tabItem(for: section)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Tabs row on a display without a notch, with the close button and the Agents tab's controls
    private var tabBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(tabs.enabledTabs, id: \.self) { section in
                    tabItem(for: section)
                }
            }

            Spacer()

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
                    ExpandedMusicView(musicStore: NowPlayingStore.shared, animation: animation)
                case .clipboard:
                    ClipboardView(store: appState.clipboardStore)
                case .files:
                    ShelfView()
                case .agents:
                    // Drawn by the Agents plugin that ships in the app
                    PluginTabView(pluginID: PluginStore.shared.replacesBuiltInTab(.agents) ?? "agents")
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

    private func tabItem(for section: IslandTab) -> some View {
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
