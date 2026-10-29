import Foundation

/// Kept in bounds as the island reads them (PluginMessage)
extension PluginMedia {
    var trimmed: PluginMedia {
        var media = self
        media.title = PluginMessage.cut(title)
        media.artist = PluginMessage.cut(artist)
        media.album = PluginMessage.cut(album)
        media.elapsed = elapsed.map { max($0.isFinite ? $0 : 0, 0) }
        media.duration = duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        media.rate = rate.map { $0.isFinite ? min(max($0, 0), 16) : 1 }
        return media
    }
}

extension PluginLyricLine {
    var trimmed: PluginLyricLine {
        PluginLyricLine(time: time.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }, text: PluginMessage.cut(text))
    }
}
