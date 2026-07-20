import Foundation
import UIKit
import CryptoKit

/// Disk + memory cache for remote images, keyed by URL.
/// Object photos get a new URL on upload, so an unchanged URL reuses the cache.
actor ImageCache {
    static let shared = ImageCache()

    private var memory: [String: Data] = [:]
    private let directory: URL
    private let session: URLSession

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        directory = base.appendingPathComponent("CoKeepImageCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let config = URLSessionConfiguration.default
        // Prefer our own cache; avoid stale shared URLCache surprises for object photos.
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config)
    }

    /// Returns a cached image for `url`, downloading once when missing.
    func image(for url: URL) async -> UIImage? {
        let key = Self.key(for: url)

        if let data = memory[key], let image = UIImage(data: data) {
            return image
        }

        let fileURL = directory.appendingPathComponent(key)
        if let data = try? Data(contentsOf: fileURL), let image = UIImage(data: data) {
            memory[key] = data
            return image
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            guard let image = UIImage(data: data) else { return nil }
            memory[key] = data
            try? data.write(to: fileURL, options: .atomic)
            return image
        } catch {
            return nil
        }
    }

    /// Drops a URL from memory and disk (e.g. after replacing an object photo).
    func remove(for url: URL) {
        let key = Self.key(for: url)
        memory.removeValue(forKey: key)
        let fileURL = directory.appendingPathComponent(key)
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func key(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
