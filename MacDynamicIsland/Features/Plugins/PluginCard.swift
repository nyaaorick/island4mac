import Foundation

/// A card in the plugin's tab (protocol 5): a row turned on its side, with a large preview. Cards sit in one
/// row above the rows and scroll sideways; tapping one with an id sends it back as an action, like a row
///
///     {"id":"c1","title":"Safari","subtitle":"2 min ago","image":{"app":"com.apple.Safari"},
///      "preview":{"text":"let x = 1"},"actions":[{"id":"delete:c1","title":"Delete","symbol":"trash"}]}
///     {"id":"c2","title":"Report.pdf","preview":{"image":{"file":"/Users/me/Report.pdf"}},"file":"/Users/me/Report.pdf"}
struct PluginCard: Decodable, Equatable, Identifiable {
    var id: String?
    var title: String
    var subtitle: String?
    var symbol: String?
    /// Small, beside the title (an app icon)
    var image: PluginImage?
    /// The large part of the card; without one, the image or symbol shows there instead
    var preview: PluginCardPreview?
    /// A file the card stands for: you can drag the card out as that file
    var file: String?
    /// Secondary actions, on hover and in its context menu
    var actions: [PluginRowAction]?

    var trimmed: PluginCard {
        PluginCard(id: id, title: PluginMessage.cut(title), subtitle: PluginMessage.cut(subtitle), symbol: symbol, image: image,
                   preview: preview?.trimmed, file: file,
                   actions: actions.map { Array($0.prefix(PluginRowAction.maxCount)).map(\.trimmed) })
    }
}

/// What a card shows large: a few lines of text, or a picture
///
///     {"text":"let x = 1"}
///     {"image":{"file":"/Users/me/photo.png"}}
enum PluginCardPreview: Decodable, Equatable {
    case text(String)
    case image(PluginImage)

    private enum CodingKeys: String, CodingKey { case text, image }

    enum DecodeError: Error { case empty }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let text = try container.decodeIfPresent(String.self, forKey: .text) {
            self = .text(text)
        } else if let image = try container.decodeIfPresent(PluginImage.self, forKey: .image) {
            self = .image(image)
        } else {
            throw DecodeError.empty
        }
    }

    var trimmed: PluginCardPreview {
        if case .text(let text) = self { return .text(String(text.prefix(PluginMessage.maxSubtitleLength))) }
        return self
    }
}
