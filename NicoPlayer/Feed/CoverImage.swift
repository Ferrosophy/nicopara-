import SwiftUI
import UIKit

/// A video cover that always fills its frame, cropping the overflow. Place it in an overlay (or
/// give it a frame). Many Niconico covers have bars baked into the image (Niconico's own 16:9 /
/// 4:3 resizes, or the uploader's letterboxed video), so those are cut off before filling.
struct CoverImage: View {
    let url: URL?
    @State private var loaded: (url: URL, image: UIImage)?

    var body: some View {
        Color.clear
            .overlay {
                if let loaded, loaded.url == url {
                    Image(uiImage: loaded.image).resizable().scaledToFill()
                }
            }
            .clipped()
            .task(id: url) {
                guard let url, let image = await CoverLoader.image(for: url) else { return }
                loaded = (url, image)
            }
    }
}

@MainActor
enum CoverLoader {
    private static let cache = NSCache<NSURL, UIImage>()

    /// The cover with its bars removed, cached in memory.
    static func image(for url: URL) async -> UIImage? {
        if let hit = cache.object(forKey: url as NSURL) { return hit }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        guard let image = await Task.detached(operation: { trimmed(data) }).value else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }

    /// Cuts dark bands off each edge: an edge line counts as a bar when nearly all of it is
    /// close to that edge's colour. Each side loses at most 30%, so a plain background
    /// in the picture itself is never eaten away.
    nonisolated static func trimmed(_ data: Data) -> UIImage? {
        guard let source = UIImage(data: data) else { return nil }
        guard let cg = source.cgImage, cg.width > 16, cg.height > 16 else { return source }
        let width = cg.width, height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return source }

        func pixel(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let i = (y * width + x) * 4
            return (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]))
        }
        func close(_ a: (Int, Int, Int), _ b: (Int, Int, Int)) -> Bool {
            abs(a.0 - b.0) <= 32 && abs(a.1 - b.1) <= 32 && abs(a.2 - b.2) <= 32
        }
        /// Whether a whole line (`count` samples) matches `color`, allowing 3% JPEG noise.
        /// Only dark bands count: a white edge is usually the picture's own background.
        func isBar(_ count: Int, _ color: (Int, Int, Int), _ sample: (Int) -> (Int, Int, Int)) -> Bool {
            guard max(color.0, color.1, color.2) <= 40 else { return false }
            var misses = 0
            for i in 0..<count where !close(sample(i), color) {
                misses += 1
                if misses * 100 > count * 3 { return false }
            }
            return true
        }

        var top = 0, bottom = height, left = 0, right = width
        let rowLimit = height * 3 / 10, columnLimit = width * 3 / 10

        let topColor = pixel(width / 2, 0)
        while top < rowLimit, isBar(width, topColor, { pixel($0, top) }) { top += 1 }
        let bottomColor = pixel(width / 2, height - 1)
        while height - bottom < rowLimit, isBar(width, bottomColor, { pixel($0, bottom - 1) }) { bottom -= 1 }

        let rows = bottom - top
        let leftColor = pixel(0, top + rows / 2)
        while left < columnLimit, isBar(rows, leftColor, { pixel(left, top + $0) }) { left += 1 }
        let rightColor = pixel(width - 1, top + rows / 2)
        while width - right < columnLimit, isBar(rows, rightColor, { pixel(right - 1, top + $0) }) { right -= 1 }

        guard top > 0 || left > 0 || bottom < height || right < width,
              let cropped = cg.cropping(to: CGRect(x: left, y: top, width: right - left, height: bottom - top))
        else { return source }
        return UIImage(cgImage: cropped, scale: source.scale, orientation: source.imageOrientation)
    }
}
