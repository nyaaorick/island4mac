//
//  SearchEngine.swift
//  Mac灵动岛
//
//  Fuzzy search and filtering engine for clipboard items
//

import Foundation

final class SearchEngine {
    
    // MARK: - Filter Options
    
    enum ContentFilter: String, CaseIterable, Identifiable {
        case all
        case text
        case images
        case links
        case files
        case pinned
        
        var id: String { rawValue }
        
        var displayName: String {
            switch self {
            case .all: return "All"
            case .text: return "Text"
            case .images: return "Images"
            case .links: return "Links"
            case .files: return "Files"
            case .pinned: return "Pinned"
            }
        }
        
        var icon: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .text: return "doc.plaintext"
            case .images: return "photo"
            case .links: return "link"
            case .files: return "doc"
            case .pinned: return "pin.fill"
            }
        }
        
        func matches_v1(_ item: IslandClipItem) -> Bool {
            switch self {
            case .all:
                return true
            case .text:
                return item.type == .text || item.type == .code
            case .images:
                return item.type == .image
            case .links:
                return item.type == .url
            case .files:
                return item.content.hasPrefix("file://")
            case .pinned:
                return item.isPinned
            }
        }
    }
}
