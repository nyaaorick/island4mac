import Foundation

/// One thing you copied: text, a link, code or a picture, and the app it came from
struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let content: String
    let type: ItemType
    let timestamp: Date
    let sourceBundleID: String?
    let sourceAppName: String?
    let imageData: Data?
    
    enum ItemType: String, Codable {
        case text, image, url, code
    }
    
    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
    
    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        return lhs.id == rhs.id
    }

    init(id: UUID = UUID(), content: String, type: ItemType, timestamp: Date = Date(), sourceBundleID: String?, sourceAppName: String?, imageData: Data?) {
        self.id = id
        self.content = content
        self.type = type
        self.timestamp = timestamp
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName
        self.imageData = imageData
    }
}
