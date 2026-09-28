//
//  MusicControlButton.swift
//  MacDynamicIsland
//
//  Stage 1: Music control button types for configurable toolbar
//

import Foundation

enum MusicControlButton: String, Codable, CaseIterable, Identifiable {
    case shuffle
    case previous
    case playPause
    case next
    case repeatMode
    case volume
    case favorite
    case goBackward
    case goForward
    case none
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .shuffle: return "Shuffle"
        case .previous: return "Previous"
        case .playPause: return "Play/Pause"
        case .next: return "Next"
        case .repeatMode: return "Repeat"
        case .volume: return "Volume"
        case .favorite: return "Favorite"
        case .goBackward: return "Go Backward 15s"
        case .goForward: return "Go Forward 15s"
        case .none: return "None"
        }
    }
    
    var icon: String {
        switch self {
        case .shuffle: return "shuffle"
        case .previous: return "backward.fill"
        case .playPause: return "play.fill"
        case .next: return "forward.fill"
        case .repeatMode: return "repeat"
        case .volume: return "speaker.wave.2.fill"
        case .favorite: return "heart"
        case .goBackward: return "gobackward.15"
        case .goForward: return "goforward.15"
        case .none: return "minus"
        }
    }
    
    static let defaultSlots: [MusicControlButton] = [
        .previous,
        .playPause,
        .next,
        .volume,
        .favorite
    ]
    
    static let minSlotCount = 3
    static let maxSlotCount = 7
}

// MARK: - Repeat Mode

enum MusicRepeatMode: String, Codable {
    case off
    case all
    case one
}
