import Foundation
import OSLog

/// 歌词服务 - 支持多个音乐平台获取歌词
final class LyricsService {
    static let shared = LyricsService()
    
    private let logger = os.Logger(subsystem: "com.maclingdonggao.overlay", category: "lyrics")
    private var cache: [String: LyricsResult] = [:]
    
    struct LyricsResult {
        let plainText: String
        let syncedLyrics: [(timeInSeconds: Double, line: String)]
        let source: String
    }
    
    private init() {}
    
    /// 获取歌词（根据设置选择来源）
    func fetchLyrics(title: String, artist: String, album: String? = nil) async -> LyricsResult? {
        let cacheKey = "\(title)_\(artist)".lowercased()
        
        // 检查缓存
        if let cached = cache[cacheKey] {
            #if DEBUG
            print("🎵 [LyricsService] 使用缓存歌词: \(title)")
            #endif
            return cached
        }
        
        // 获取用户设置的歌词源
        let source = SettingsDefaults.shared.get(SettingsDefaults.lyricsSource)
        
        #if DEBUG
        print("🎵 [LyricsService] 开始获取歌词: \(title) - \(artist) [Source: \(source)]")
        #endif
        
        // 根据设置路由请求
        switch source {
        case "lrclib":
            if let result = await fetchFromLrcLib(title: title, artist: artist, album: album) {
                cache[cacheKey] = result
                return result
            }
            
        case "netease":
            if let result = await fetchFromNetease(title: title, artist: artist) {
                cache[cacheKey] = result
                return result
            }
            
        case "auto":
            fallthrough // 自动模式：尝试所有
            
        default:
            // 1️⃣ 优先使用 LrcLib（开源、免费、稳定）
            if let result = await fetchFromLrcLib(title: title, artist: artist, album: album) {
                cache[cacheKey] = result
                #if DEBUG
                print("🎵 [LyricsService] ✅ 从 LrcLib 获取成功")
                #endif
                return result
            }
            
            // 2️⃣ 尝试网易云音乐 API
            if let result = await fetchFromNetease(title: title, artist: artist) {
                cache[cacheKey] = result
                #if DEBUG
                print("🎵 [LyricsService] ✅ 从网易云获取成功")
                #endif
                return result
            }
            
            // 3️⃣ 尝试 QQ 音乐 API
            if let result = await fetchFromQQMusic(title: title, artist: artist) {
                cache[cacheKey] = result
                #if DEBUG
                print("🎵 [LyricsService] ✅ 从QQ音乐获取成功")
                #endif
                return result
            }
        }
        
        #if DEBUG
        print("🎵 [LyricsService] ❌ 未找到歌词: \(title) - \(artist)")
        #endif
        return nil
    }
    
    // MARK: - 网易云音乐 API
    
    private func fetchFromNetease(title: String, artist: String) async -> LyricsResult? {
        // 网易云音乐 API 调用（优先使用公共服务端，fallback 到本地 3000 端口）
        // API 文档: https://neteasecloudmusicapi.vercel.app
        // 步骤:
        // 1. 搜索歌曲 ID: /search?keywords=xxx
        // 2. 获取歌词: /lyric?id=xxx

        logger.debug("尝试从网易云音乐获取歌词: \(title) - \(artist)")

        let bases = neteaseAPIBases()
        for apiBase in bases {
            guard let searchURL = buildNeteaseSearchURL(apiBase: apiBase, title: title, artist: artist) else {
                continue
            }

            do {
                // 搜索歌曲
                let (searchData, _) = try await URLSession.shared.data(from: searchURL)
                guard let songId = parseNeteaseSongId(from: searchData) else {
                    continue
                }

                // 获取歌词
                guard let lyricsURL = buildNeteaseLyricsURL(apiBase: apiBase, songId: songId) else {
                    continue
                }

                let (lyricsData, _) = try await URLSession.shared.data(from: lyricsURL)
                if let parsed = parseNeteaseLyrics(from: lyricsData) {
                    return parsed
                }
            } catch {
                // Try next base
                continue
            }
        }

        return nil
    }

    private func neteaseAPIBases() -> [String] {
        // Prefer public hosted API first (no local setup required), then fall back to local server.
        [
            "https://neteasecloudmusicapi.vercel.app",
            "http://localhost:3000"
        ]
    }

    private func buildNeteaseSearchURL(apiBase: String, title: String, artist: String) -> URL? {
        let keywords = "\(title) \(artist)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "\(apiBase)/search?keywords=\(keywords)&limit=1")
    }

    private func buildNeteaseLyricsURL(apiBase: String, songId: String) -> URL? {
        return URL(string: "\(apiBase)/lyric?id=\(songId)")
    }
    
    private func parseNeteaseSongId(from data: Data) -> String? {
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let result = json["result"] as? [String: Any],
               let songs = result["songs"] as? [[String: Any]],
               let firstSong = songs.first,
               let id = firstSong["id"] as? Int {
                return String(id)
            }
        } catch {
            logger.error("解析网易云搜索结果失败: \(error.localizedDescription)")
        }
        return nil
    }
    
    private func parseNeteaseLyrics(from data: Data) -> LyricsResult? {
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let lrc = json["lrc"] as? [String: Any],
               let lyricText = lrc["lyric"] as? String {
                
                // 解析 LRC 格式歌词；一行都没解析出来就不算找到，交给下一个来源
                let synced = Self.parseLRC(lyricText)
                guard !synced.isEmpty else { return nil }
                let plain = synced.map { $0.line }.joined(separator: "\n")
                
                return LyricsResult(
                    plainText: plain,
                    syncedLyrics: synced,
                    source: "Netease Cloud Music"
                )
            }
        } catch {
            logger.error("解析网易云歌词失败: \(error.localizedDescription)")
        }
        return nil
    }
    
    // MARK: - QQ 音乐 API
    
    private func fetchFromQQMusic(title: String, artist: String) async -> LyricsResult? {
        // 🚧 TODO: 实现 QQ 音乐 API 调用
        logger.debug("尝试从 QQ 音乐获取歌词: \(title) - \(artist)")
        return nil
    }
    
    // MARK: - LrcLib API（开源免费）
    // 与 Boring Notch 保持一致，使用 /api/search 端点
    
    private func fetchFromLrcLib(title: String, artist: String, album: String?) async -> LyricsResult? {
        logger.debug("尝试从 LrcLib 获取歌词: \(title) - \(artist)")
        
        // 标准化查询参数（去除特殊字符）
        let cleanTitle = normalizedQuery(title)
        let cleanArtist = normalizedQuery(artist)
        
        guard let encodedTitle = cleanTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedArtist = cleanArtist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        
        // 使用 search API（与 Boring Notch 一致）
        let urlString = "https://lrclib.net/api/search?track_name=\(encodedTitle)&artist_name=\(encodedArtist)"
        
        guard let url = URL(string: urlString) else {
            return nil
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            // 检查 HTTP 状态码
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                logger.error("LrcLib API 返回错误状态码: \(httpResponse.statusCode)")
                return nil
            }
            
            return parseLrcLibSearchResponse(from: data)
        } catch {
            logger.error("LrcLib API 错误: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// 标准化查询字符串（去除变音符号和特殊字符）
    private func normalizedQuery(_ string: String) -> String {
        string
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: "\u{FFFD}", with: "")
    }
    
    /// 解析 LrcLib search API 响应（返回数组）
    private func parseLrcLibSearchResponse(from data: Data) -> LyricsResult? {
        do {
            // Search API 返回的是数组；同一首歌常有好几个版本，优先选带同步歌词的
            if let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let first = jsonArray.first(where: { !($0["syncedLyrics"] as? String ?? "").isEmpty }) ?? jsonArray.first {
                
                let syncedLRC = first["syncedLyrics"] as? String ?? ""
                let plainLyrics = first["plainLyrics"] as? String ?? ""
                
                // 优先使用同步歌词
                let synced = Self.parseLRC(syncedLRC)
                let resolvedPlain = plainLyrics.isEmpty ? syncedLRC : plainLyrics
                
                if synced.isEmpty && resolvedPlain.isEmpty {
                    return nil
                }
                
                return LyricsResult(
                    plainText: resolvedPlain.trimmingCharacters(in: .whitespacesAndNewlines),
                    syncedLyrics: synced,
                    source: "LrcLib"
                )
            }
        } catch {
            logger.error("解析 LrcLib 响应失败: \(error.localizedDescription)")
        }
        return nil
    }
    
    // MARK: - LRC 格式解析
    
    /// 解析 LRC 格式歌词
    /// 时间戳支持 [mm:ss]、[mm:ss.x]、[mm:ss.xx] 和 [mm:ss.xxx]（网易云常用三位毫秒）；
    /// 一行可以带好几个时间戳，副歌重复时常这样写
    static func parseLRC(_ lrcText: String) -> [(timeInSeconds: Double, line: String)] {
        guard let timestamp = try? NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]"#) else {
            return []
        }
        var result: [(timeInSeconds: Double, line: String)] = []

        for rawLine in lrcText.components(separatedBy: .newlines) {
            let line = rawLine as NSString
            var times: [Double] = []
            var textStart = 0
            // 第一个时间戳在哪都行，后面的要一个紧接一个
            var options: NSRegularExpression.MatchingOptions = []

            while let match = timestamp.firstMatch(in: rawLine, options: options,
                                                   range: NSRange(location: textStart, length: line.length - textStart)) {
                let minutes = Double(line.substring(with: match.range(at: 1))) ?? 0
                let seconds = Double(line.substring(with: match.range(at: 2))) ?? 0
                // 小数部分按位数算：.3 是 0.3 秒，.36 是 0.36 秒，.360 也是 0.36 秒
                let fraction = match.range(at: 3).location == NSNotFound
                    ? 0 : Double("0." + line.substring(with: match.range(at: 3))) ?? 0
                times.append(minutes * 60 + seconds + fraction)
                textStart = match.range.location + match.range.length
                options = .anchored
            }

            // 提取歌词文本（时间戳之后的部分）；[ar:歌手] 这类标签行没有时间戳，自然跳过
            let text = line.substring(from: textStart).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            result += times.map { (timeInSeconds: $0, line: text) }
        }

        return result.sorted { $0.timeInSeconds < $1.timeInSeconds }
    }
    
    /// 清除缓存
    func clearCache() {
        cache.removeAll()
    }
}
