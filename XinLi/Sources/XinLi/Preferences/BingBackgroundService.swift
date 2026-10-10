import CryptoKit
import Foundation
import ImageIO

struct BingBackgroundMetadata: Codable, Equatable, Sendable {
    let imageURL: URL
    let copyright: String
    let copyrightURL: URL?
    let title: String
    let startDate: String
}

struct BingCachedBackground: Equatable, Sendable {
    let metadata: BingBackgroundMetadata
    let imageFileURL: URL
}

/// Bing photos remain in the user's runtime cache, with their original attribution.
/// The app bundle does not contain or redistribute these photographs.
struct BingBackgroundService: Sendable {
    static let archiveURL = URL(string: "https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=8&mkt=zh-CN")!
    static let maximumImageBytes = 12_000_000
    static let maximumMetadataBytes = 256_000
    private let session: URLSession
    let cacheDirectory: URL

    init(session: URLSession = .shared, cacheDirectory: URL? = nil) {
        self.session = session
        self.cacheDirectory = cacheDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ChronoCal/Bing", isDirectory: true)
    }

    func cachedBackground() -> BingCachedBackground? {
        guard let document = try? boundedFile(at: manifestURL, limit: Self.maximumMetadataBytes),
              let cache = try? JSONDecoder().decode(CacheManifest.self, from: document),
              cache.schemaVersion == 1, Self.isImageURL(cache.metadata.imageURL),
              cache.metadata.copyrightURL.map(Self.isCopyrightURL) ?? true,
              cache.imageSHA256.count == 64,
              cache.imageSHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              cache.fileName == "bing-\(cache.imageSHA256).image" else { return nil }
        let file = cacheDirectory.appendingPathComponent(cache.fileName)
        guard let image = try? boundedFile(at: file, limit: Self.maximumImageBytes),
              Self.digest(image) == cache.imageSHA256, Self.validImage(image) else { return nil }
        return BingCachedBackground(metadata: cache.metadata, imageFileURL: file)
    }

    func refresh() async throws -> BingCachedBackground {
        let previous = cachedBackground()
        let json = try await fetch(Self.archiveURL, kind: .archive, maximumBytes: Self.maximumMetadataBytes)
        guard let archive = try? JSONDecoder().decode(Archive.self, from: json) else { throw BingBackgroundError.invalidMetadata }
        var seen: Set<URL> = []
        let choices = archive.images.prefix(8).compactMap { item -> BingBackgroundMetadata? in
            // A missing flag cannot establish that this photo allows wallpaper download.
            guard item.wp == true,
                  let url = URL(string: item.url, relativeTo: Self.archiveURL)?.absoluteURL,
                  Self.isImageURL(url), seen.insert(url).inserted,
                  !item.copyright.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  item.copyright.count <= 2_048, (item.title?.count ?? 0) <= 512 else { return nil }
            let link = item.copyrightlink.flatMap(URL.init(string:)).flatMap { Self.isCopyrightURL($0) ? $0 : nil }
            return BingBackgroundMetadata(imageURL: url, copyright: item.copyright,
                                          copyrightURL: link, title: item.title ?? "Bing 每日风景", startDate: item.startdate ?? "")
        }
        guard !choices.isEmpty else { throw BingBackgroundError.noEligibleImages }
        let selected: BingBackgroundMetadata
        if let current = previous?.metadata.imageURL, let index = choices.firstIndex(where: { $0.imageURL == current }) {
            guard choices.count > 1 else { throw BingBackgroundError.noOtherImages }
            selected = choices[(index + 1) % choices.count]
        } else { selected = choices[0] }
        let image = try await fetch(selected.imageURL, kind: .image, maximumBytes: Self.maximumImageBytes)
        guard Self.validImage(image) else { throw BingBackgroundError.invalidImage }
        try Task.checkCancellation()
        return try store(image, metadata: selected, previous: previous)
    }

    private var manifestURL: URL { cacheDirectory.appendingPathComponent("bing-background.json") }

    private func fetch(_ url: URL, kind: ResourceKind, maximumBytes: Int) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        request.setValue(kind == .archive ? "application/json" : "image/jpeg,image/png,image/webp", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request, delegate: BingRedirectValidator(kind: kind))
        defer { bytes.task.cancel() }
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode),
              let finalURL = response.url, kind.accepts(finalURL) else { throw BingBackgroundError.invalidResponse }
        let mime = response.mimeType?.lowercased() ?? ""
        guard kind == .archive ? mime == "application/json" : ["image/jpeg", "image/png", "image/webp"].contains(mime) else {
            throw BingBackgroundError.invalidResponse
        }
        guard response.expectedContentLength <= maximumBytes else { throw BingBackgroundError.tooLarge }
        var result = Data()
        result.reserveCapacity(min(maximumBytes, max(0, Int(response.expectedContentLength))))
        for try await byte in bytes {
            guard result.count < maximumBytes else { throw BingBackgroundError.tooLarge }
            result.append(byte)
        }
        guard !result.isEmpty else { throw BingBackgroundError.invalidResponse }
        return result
    }

    private func store(_ image: Data, metadata: BingBackgroundMetadata, previous: BingCachedBackground?) throws -> BingCachedBackground {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let hash = Self.digest(image)
        let fileName = "bing-\(hash).image"
        let file = cacheDirectory.appendingPathComponent(fileName)
        let manifest = CacheManifest(schemaVersion: 1, metadata: metadata, fileName: fileName, imageSHA256: hash)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // The metadata pointer changes only after a validated image has been written.
        // Failure leaves the old metadata and photograph usable offline.
        try image.write(to: file, options: .atomic)
        do { try encoder.encode(manifest).write(to: manifestURL, options: .atomic) }
        catch {
            if previous?.imageFileURL != file { try? FileManager.default.removeItem(at: file) }
            throw error
        }
        if let previous, previous.imageFileURL != file { try? FileManager.default.removeItem(at: previous.imageFileURL) }
        return BingCachedBackground(metadata: metadata, imageFileURL: file)
    }

    private func boundedFile(at url: URL, limit: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= limit else { throw BingBackgroundError.tooLarge }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= limit else { throw BingBackgroundError.tooLarge }
        return data
    }

    private static func validImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 12_000, height <= 12_000,
              width * height <= 30_000_000,
              CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) != nil else { return false }
        return true
    }

    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static let bingHosts: Set<String> = ["bing.com", "www.bing.com", "cn.bing.com"]
    private static func isBingURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host.map { bingHosts.contains($0.lowercased()) } == true &&
        url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
    }
    private static func isImageURL(_ url: URL) -> Bool {
        guard isBingURL(url), url.path == "/th", url.fragment == nil,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return false }
        let ids = items.filter { $0.name == "id" }
        guard ids.count == 1, let id = ids[0].value, id.hasPrefix("OHR."), id.count < 512,
              [".jpg", ".jpeg", ".png", ".webp"].contains(where: { id.lowercased().hasSuffix($0) }) else { return false }
        return !id.contains("/") && !id.contains("\\") && !id.contains("..")
    }
    private static func isCopyrightURL(_ url: URL) -> Bool { isBingURL(url) && url.path == "/search" }

    private struct Archive: Decodable { let images: [ArchiveImage] }
    private struct ArchiveImage: Decodable {
        let url: String
        let copyright: String
        let copyrightlink: String?
        let title: String?
        let startdate: String?
        let wp: Bool?
    }
    private struct CacheManifest: Codable {
        let schemaVersion: Int
        let metadata: BingBackgroundMetadata
        let fileName: String
        let imageSHA256: String
    }
    private enum ResourceKind: Sendable {
        case archive, image
        func accepts(_ url: URL) -> Bool {
            switch self {
            case .archive: return isBingURL(url) && url.path == "/HPImageArchive.aspx"
            case .image: return isImageURL(url)
            }
        }
    }
    private final class BingRedirectValidator: NSObject, URLSessionTaskDelegate {
        let kind: ResourceKind
        init(kind: ResourceKind) { self.kind = kind }
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(request.url.map(kind.accepts) == true ? request : nil)
        }
    }
}

enum BingBackgroundError: LocalizedError {
    case invalidMetadata, noEligibleImages, noOtherImages, invalidResponse, tooLarge, invalidImage
    var errorDescription: String? {
        switch self {
        case .invalidMetadata: "Bing 风景信息无法读取，请稍后重试。"
        case .noEligibleImages: "Bing 最近没有允许下载的风景图片。"
        case .noOtherImages: "暂时没有其他可用风景，请稍后重试。"
        case .invalidResponse: "Bing 返回的图片或网络响应无效，已保留原背景。"
        case .tooLarge: "Bing 图片或信息超出大小限制，已保留原背景。"
        case .invalidImage: "Bing 图片无法解码，已保留原背景。"
        }
    }
}
