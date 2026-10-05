import Foundation
import AppKit
import UniformTypeIdentifiers

extension NSItemProvider {
    
    // MARK: - Async Wrappers
    
    /// Internal async wrapper for loadItem(forTypeIdentifier:options:completionHandler:)
    private func loadItemAsync(forTypeIdentifier typeIdentifier: String, options: [AnyHashable : Any]? = nil) async throws -> NSSecureCoding? {
        try await withCheckedThrowingContinuation { continuation in
            self.loadItem(forTypeIdentifier: typeIdentifier, options: options) { item, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: item)
                }
            }
        }
    }

    /// Async wrapper for loadDataRepresentation(forTypeIdentifier:completionHandler:)
    private func loadDataRepresentationAsync(forTypeIdentifier typeIdentifier: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            self.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let data = data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: NSError(domain: "NSItemProvider", code: -2, userInfo: [NSLocalizedDescriptionKey: "No data for typeIdentifier \(typeIdentifier)"]))
                }
            }
        }
    }

    // MARK: - Safe Extractors
    
    func extractFileURL() async -> URL? {
        // 1) Prefer dataRepresentation: avoids NSSecureCoding spam and decodes reliably
        if let data = try? await loadDataRepresentationAsync(forTypeIdentifier: UTType.fileURL.identifier),
           let url = URL(dataRepresentation: data, relativeTo: nil) {
            return url
        }
        
        // 2) Fallback to loadItem (some providers only support this)
        guard hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { return nil }
        
        do {
            let item = try await loadItemAsync(forTypeIdentifier: UTType.fileURL.identifier)
            
            if let url = item as? URL {
                return url
            } else if let data = item as? Data {
                // ✅ Correct decode for fileURL payloads
                if let url = URL(dataRepresentation: data, relativeTo: nil) {
                    return url
                }
                
                // Fallback: try string decode
                if let string = String(data: data, encoding: .utf8) {
                    if let url = URL(string: string) { return url }
                    if string.hasPrefix("/") { return URL(fileURLWithPath: string) }
                }
                
                // Last resort: bookmark
                var isStale = false
                return try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            } else if let string = item as? String {
                if let url = URL(string: string) { return url }
                if string.hasPrefix("/") { return URL(fileURLWithPath: string) }
            }
        } catch {
            print("❌ [NSItemProvider] Failed to load fileURL: \(error)")
        }
        return nil
    }
    
    func extractURL() async -> URL? {
        // Prefer dataRepresentation for robustness
        if let data = try? await loadDataRepresentationAsync(forTypeIdentifier: UTType.url.identifier),
           let url = URL(dataRepresentation: data, relativeTo: nil) {
            return url
        }
        
        guard hasItemConformingToTypeIdentifier(UTType.url.identifier) else { return nil }
        
        do {
            let item = try await loadItemAsync(forTypeIdentifier: UTType.url.identifier)
            if let url = item as? URL { return url }
            if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) { return url }
            if let string = item as? String { return URL(string: string) }
        } catch {
            print("❌ [NSItemProvider] Failed to load URL: \(error)")
        }
        return nil
    }

    func extractText() async -> String? {
        let textTypes = [UTType.utf8PlainText.identifier, UTType.plainText.identifier, UTType.text.identifier]
        
        for typeIdentifier in textTypes {
            // Prefer dataRepresentation to avoid decoding warnings
            if let data = try? await loadDataRepresentationAsync(forTypeIdentifier: typeIdentifier),
               let string = String(data: data, encoding: .utf8),
               !string.isEmpty {
                return string
            }
            
            // Fallback to loadItem
            if self.hasItemConformingToTypeIdentifier(typeIdentifier) {
                do {
                    let item = try await loadItemAsync(forTypeIdentifier: typeIdentifier)
                    if let string = item as? String { return string }
                    if let data = item as? Data, let string = String(data: data, encoding: .utf8) { return string }
                } catch {
                    continue
                }
            }
        }
        return nil
    }
}
