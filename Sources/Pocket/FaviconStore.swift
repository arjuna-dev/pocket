import AppKit
import CryptoKit
import Foundation

actor FaviconStore {
    static let shared = FaviconStore()

    private let session: URLSession
    private var memory: [String: Data] = [:]
    private var inflight: [String: Task<Data?, Never>] = [:]

    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36"
    private static let cacheLifetime: TimeInterval = 7 * 24 * 60 * 60

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.httpMaximumConnectionsPerHost = 6
        session = URLSession(configuration: configuration)
    }

    func imageData(for siteURL: URL) async -> Data? {
        guard siteURL.host != nil else { return nil }
        let key = cacheKey(for: siteURL)
        if let cached = memory[key] {
            return cached
        }
        if let stored = diskImage(for: key) {
            memory[key] = stored
            return stored
        }
        if let existing = inflight[key] {
            return await existing.value
        }

        let task = Task { () -> Data? in
            await self.downloadImage(for: siteURL)
        }
        inflight[key] = task
        let data = await task.value
        inflight[key] = nil
        if let data {
            memory[key] = data
            saveDisk(data, key: key)
        }
        return data
    }

    private func downloadImage(for siteURL: URL) async -> Data? {
        var candidates: [URL] = []
        if let document = await fetchDocument(for: siteURL) {
            candidates = iconLinks(in: document.html, baseURL: document.finalURL)
        }
        if let fallback = defaultIconURL(for: siteURL), !candidates.contains(fallback) {
            candidates.append(fallback)
        }

        for candidate in candidates.prefix(4) {
            if let data = await imageData(at: candidate) {
                return data
            }
        }
        return nil
    }

    private func fetchDocument(for siteURL: URL) async -> (html: String, finalURL: URL)? {
        var request = URLRequest(url: siteURL)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(
            "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            forHTTPHeaderField: "Accept"
        )
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("document", forHTTPHeaderField: "Sec-Fetch-Dest")
        request.setValue("navigate", forHTTPHeaderField: "Sec-Fetch-Mode")
        request.setValue("none", forHTTPHeaderField: "Sec-Fetch-Site")
        request.setValue("1", forHTTPHeaderField: "Upgrade-Insecure-Requests")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            return nil
        }

        let html = String(decoding: data.prefix(512 * 1024), as: UTF8.self)
        return (html, http.url ?? siteURL)
    }

    private func imageData(at url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("image/avif,image/webp,image/png,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              looksLikeImage(data, contentType: http.value(forHTTPHeaderField: "Content-Type")) else {
            return nil
        }
        return data
    }

    private func iconLinks(in html: String, baseURL: URL) -> [URL] {
        guard let regex = try? NSRegularExpression(pattern: #"<link\b[^>]*>"#, options: [.caseInsensitive]) else {
            return []
        }

        let range = NSRange(html.startIndex..., in: html)
        var ranked: [(URL, Int)] = []
        regex.enumerateMatches(in: html, range: range) { match, _, _ in
            guard let match, let tagRange = Range(match.range, in: html) else { return }
            let tag = String(html[tagRange])
            guard let rel = attribute("rel", in: tag)?.lowercased(),
                  rel.contains("icon"),
                  !rel.contains("mask"),
                  let href = attribute("href", in: tag),
                  let resolved = resolve(href, base: baseURL) else {
                return
            }

            let type = attribute("type", in: tag)?.lowercased() ?? ""
            if type.contains("svg") || resolved.pathExtension.lowercased() == "svg" {
                return
            }

            let size = declaredSize(attribute("sizes", in: tag))
            ranked.append((resolved, score(size: size, rel: rel, type: type, url: resolved)))
        }

        var seen = Set<String>()
        return ranked
            .sorted { $0.1 > $1.1 }
            .compactMap { candidate in
                let identity = candidate.0.absoluteString
                guard seen.insert(identity).inserted else { return nil }
                return candidate.0
            }
    }

    private func score(size: Int, rel: String, type: String, url: URL) -> Int {
        var pixels = size
        if pixels == 0 {
            pixels = rel.contains("apple") ? 180 : 32
        }

        var value = pixels
        if pixels > 512 {
            value = 420
        }
        if type.contains("png") || url.pathExtension.lowercased() == "png" {
            value += 24
        } else if type.contains("webp") || url.pathExtension.lowercased() == "webp" {
            value += 18
        }
        if rel.contains("apple") {
            value += 36
        }
        return value
    }

    private func declaredSize(_ sizes: String?) -> Int {
        guard let sizes else { return 0 }
        let lowered = sizes.lowercased()
        if lowered == "any" { return 0 }
        let numbers = lowered.split { !$0.isNumber }.compactMap { Int($0) }
        return numbers.max() ?? 0
    }

    private func attribute(_ name: String, in tag: String) -> String? {
        let pattern = #"(?i)(?:^|[\s/])"#
            + NSRegularExpression.escapedPattern(for: name)
            + #"\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else {
            return nil
        }
        for index in 1..<match.numberOfRanges {
            guard let range = Range(match.range(at: index), in: tag) else { continue }
            let value = String(tag[range])
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&quot;", with: "\"")
            return value
        }
        return nil
    }

    private func resolve(_ href: String, base: URL) -> URL? {
        let cleaned = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !cleaned.hasPrefix("data:") else { return nil }
        guard let url = URL(string: cleaned, relativeTo: base)?.absoluteURL,
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            return nil
        }
        return url
    }

    private func defaultIconURL(for siteURL: URL) -> URL? {
        guard let host = siteURL.host, let scheme = siteURL.scheme else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = "/favicon.ico"
        return components.url
    }

    private func looksLikeImage(_ data: Data, contentType: String?) -> Bool {
        let type = (contentType ?? "").lowercased()
        if type.contains("text/") || type.contains("json") || type.contains("javascript") {
            return false
        }
        if data.starts(with: Data([0x89, 0x50, 0x4E, 0x47])) { return true }
        if data.starts(with: Data([0xFF, 0xD8, 0xFF])) { return true }
        if data.starts(with: Data("GIF8".utf8)) { return true }
        if data.starts(with: Data([0x00, 0x00, 0x01, 0x00])) { return true }
        if data.count > 12,
           data.starts(with: Data("RIFF".utf8)),
           data[8..<12] == Data("WEBP".utf8) {
            return true
        }
        return type.contains("image/")
    }

    private func cacheKey(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.lowercased().utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func cacheFile(for key: String) -> URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pocket/favicons", isDirectory: true)
        return directory.appendingPathComponent(key)
    }

    private func diskImage(for key: String) -> Data? {
        let file = cacheFile(for: key)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              let modified = attributes[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < Self.cacheLifetime,
              let data = try? Data(contentsOf: file),
              looksLikeImage(data, contentType: nil) else {
            return nil
        }
        return data
    }

    private func saveDisk(_ data: Data, key: String) {
        let file = cacheFile(for: key)
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: file, options: .atomic)
    }
}
