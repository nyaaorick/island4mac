import Foundation
import OSLog

/// Lyrics service - fetches lyrics from multiple music platforms
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
    
    /// Fetch lyrics (the source is chosen from settings)
    func fetchLyrics(title: String, artist: String, album: String? = nil) async -> LyricsResult? {
        let cacheKey = "\(title)_\(artist)".lowercased()
        
        // Check the cache
        if let cached = cache[cacheKey] {
            #if DEBUG
            print("🎵 [LyricsService] Using cached lyrics: \(title)")
            #endif
            return cached
        }
        
        // Get the lyrics source the user chose
        let source = SettingsDefaults.shared.get(SettingsDefaults.lyricsSource)
        
        #if DEBUG
        print("🎵 [LyricsService] Fetching lyrics: \(title) - \(artist) [Source: \(source)]")
        #endif
        
        // Route the request according to the setting
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
            fallthrough // Auto mode: try all sources
            
        default:
            // 1️⃣ Prefer LrcLib (open source, free, stable)
            if let result = await fetchFromLrcLib(title: title, artist: artist, album: album) {
                cache[cacheKey] = result
                #if DEBUG
                print("🎵 [LyricsService] ✅ Fetched from LrcLib")
                #endif
                return result
            }
            
            // 2️⃣ Try the NetEase Cloud Music API
            if let result = await fetchFromNetease(title: title, artist: artist) {
                cache[cacheKey] = result
                #if DEBUG
                print("🎵 [LyricsService] ✅ Fetched from NetEase")
                #endif
                return result
            }
            
            // 3️⃣ Try the QQ Music API
            if let result = await fetchFromQQMusic(title: title, artist: artist) {
                cache[cacheKey] = result
                #if DEBUG
                print("🎵 [LyricsService] ✅ Fetched from QQ Music")
                #endif
                return result
            }
        }
        
        #if DEBUG
        print("🎵 [LyricsService] ❌ No lyrics found: \(title) - \(artist)")
        #endif
        return nil
    }
    
    // MARK: - NetEase Cloud Music API
    
    private func fetchFromNetease(title: String, artist: String) async -> LyricsResult? {
        // NetEase Cloud Music API call (prefer the public server, fall back to local port 3000)
        // API docs: https://neteasecloudmusicapi.vercel.app
        // Steps:
        // 1. Search for the song ID: /search?keywords=xxx
        // 2. Get the lyrics: /lyric?id=xxx

        logger.debug("Trying to fetch lyrics from NetEase Cloud Music: \(title) - \(artist)")

        let bases = neteaseAPIBases()
        for apiBase in bases {
            guard let searchURL = buildNeteaseSearchURL(apiBase: apiBase, title: title, artist: artist) else {
                continue
            }

            do {
                // Search for the song
                let (searchData, _) = try await URLSession.shared.data(from: searchURL)
                guard let songId = parseNeteaseSongId(from: searchData) else {
                    continue
                }

                // Get the lyrics
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
            logger.error("Failed to parse NetEase search results: \(error.localizedDescription)")
        }
        return nil
    }
    
    private func parseNeteaseLyrics(from data: Data) -> LyricsResult? {
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let lrc = json["lrc"] as? [String: Any],
               let lyricText = lrc["lyric"] as? String {
                
                // Parse the LRC lyrics; if not a single line parses it doesn't count as found, so hand over to the next source
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
            logger.error("Failed to parse NetEase lyrics: \(error.localizedDescription)")
        }
        return nil
    }
    
    // MARK: - QQ Music API
    
    private func fetchFromQQMusic(title: String, artist: String) async -> LyricsResult? {
        // 🚧 TODO: Implement the QQ Music API call
        logger.debug("Trying to fetch lyrics from QQ Music: \(title) - \(artist)")
        return nil
    }
    
    // MARK: - LrcLib API (open source, free)
    // Consistent with Boring Notch, use the /api/search endpoint
    
    private func fetchFromLrcLib(title: String, artist: String, album: String?) async -> LyricsResult? {
        logger.debug("Trying to fetch lyrics from LrcLib: \(title) - \(artist)")
        
        // Normalize the query parameters (strip special characters)
        let cleanTitle = normalizedQuery(title)
        let cleanArtist = normalizedQuery(artist)
        
        guard let encodedTitle = cleanTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedArtist = cleanArtist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        
        // Use the search API (as Boring Notch does)
        let urlString = "https://lrclib.net/api/search?track_name=\(encodedTitle)&artist_name=\(encodedArtist)"
        
        guard let url = URL(string: urlString) else {
            return nil
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            // Check the HTTP status code
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                logger.error("LrcLib API returned an error status code: \(httpResponse.statusCode)")
                return nil
            }
            
            return parseLrcLibSearchResponse(from: data)
        } catch {
            logger.error("LrcLib API error: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Normalize the query string (strip diacritics and special characters)
    private func normalizedQuery(_ string: String) -> String {
        string
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: "\u{FFFD}", with: "")
    }
    
    /// Parse the LrcLib search API response (returns an array)
    private func parseLrcLibSearchResponse(from data: Data) -> LyricsResult? {
        do {
            // The search API returns an array; a song often has several versions, so prefer one with synced lyrics
            if let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let first = jsonArray.first(where: { !($0["syncedLyrics"] as? String ?? "").isEmpty }) ?? jsonArray.first {
                
                let syncedLRC = first["syncedLyrics"] as? String ?? ""
                let plainLyrics = first["plainLyrics"] as? String ?? ""
                
                // Prefer synced lyrics
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
            logger.error("Failed to parse the LrcLib response: \(error.localizedDescription)")
        }
        return nil
    }
    
    // MARK: - LRC Parsing
    
    /// Parse LRC lyrics
    /// Timestamps may be [mm:ss], [mm:ss.x], [mm:ss.xx] or [mm:ss.xxx] (NetEase often uses three-digit milliseconds);
    /// a line can carry several timestamps, which is common when a chorus repeats
    static func parseLRC(_ lrcText: String) -> [(timeInSeconds: Double, line: String)] {
        guard let timestamp = try? NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]"#) else {
            return []
        }
        var result: [(timeInSeconds: Double, line: String)] = []

        for rawLine in lrcText.components(separatedBy: .newlines) {
            let line = rawLine as NSString
            var times: [Double] = []
            var textStart = 0
            // The first timestamp can be anywhere; the rest must follow one right after another
            var options: NSRegularExpression.MatchingOptions = []

            while let match = timestamp.firstMatch(in: rawLine, options: options,
                                                   range: NSRange(location: textStart, length: line.length - textStart)) {
                let minutes = Double(line.substring(with: match.range(at: 1))) ?? 0
                let seconds = Double(line.substring(with: match.range(at: 2))) ?? 0
                // The fractional part is read by digit count: .3 is 0.3s, .36 is 0.36s, and .360 is also 0.36s
                let fraction = match.range(at: 3).location == NSNotFound
                    ? 0 : Double("0." + line.substring(with: match.range(at: 3))) ?? 0
                times.append(minutes * 60 + seconds + fraction)
                textStart = match.range.location + match.range.length
                options = .anchored
            }

            // Extract the lyric text (the part after the timestamps); tag lines like [ar:artist] have no timestamp and are skipped naturally
            let text = line.substring(from: textStart).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            result += times.map { (timeInSeconds: $0, line: text) }
        }

        return result.sorted { $0.timeInSeconds < $1.timeInSeconds }
    }
    
    /// Clear the cache
    func clearCache() {
        cache.removeAll()
    }
}
