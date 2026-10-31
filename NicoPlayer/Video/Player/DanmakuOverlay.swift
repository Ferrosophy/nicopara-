import AVFoundation
import NicoKit
import SwiftUI

/// Draws the video's comments over the picture, Niconico-style: most scroll right to left in
/// 4 s; `ue` / `shita` ones sit centred at the top / bottom for 3 s. Size and colour follow the
/// comment's commands. Drawn every frame from the player's own clock, so it stays in sync
/// through seeks, pauses and the long-press 2x.
///
/// `translations` (comment ID → text) adds, for top / bottom comments only, a local line with
/// the translation right next to the original (below a top one, above a bottom one).
struct DanmakuOverlay: View {
    let model: PlayerModel
    let comments: [NicoComment]
    /// Merged duplicates: comment ID → how many it stands for (drawn as "×N").
    var counts: [String: Int] = [:]
    var translations: [String: String] = [:]
    var settings = DanmakuSettings()

    @State private var layout = DanmakuLayout()

    var body: some View {
        // Read here so a seek while paused redraws (the timeline is paused then).
        let _ = model.currentTime
        TimelineView(.animation(paused: !model.isPlaying)) { timeline in
            // The Canvas must depend on the timeline's date, or SwiftUI sees nothing changed
            // and never redraws it (danmaku froze where they were when switched on).
            let frame = timeline.date
            Canvas { context, size in
                _ = frame
                let seconds = model.player.currentTime().seconds
                layout.draw(in: &context, size: size, timeMs: seconds.isFinite ? seconds * 1000 : 0,
                            comments: comments, counts: counts, translations: translations, settings: settings)
            }
        }
        .opacity(settings.opacity)
        .allowsHitTesting(false)
    }
}

/// User-adjustable look of the danmaku (应用设置).
struct DanmakuSettings: Equatable {
    enum Stroke: String, CaseIterable { case shadow, outline, none }

    var opacity: Double = 0.92
    /// Multiplies the base font size.
    var scale: Double = 1
    var maxOnScreen: Int = 80
    /// Fraction of the height (from the top) danmaku may use.
    var area: Double = 1
    /// Scroll speed factor; 1 = 4 seconds across, as on the site.
    var speed: Double = 1
    var stroke: Stroke = .shadow
}

/// Lane assignment for danmaku, remembered per comment so a comment keeps its line for its
/// whole flight. Cleared when the player size changes (inline ↔ fullscreen).
@MainActor
final class DanmakuLayout {
    static let scrollMs = 4000.0
    static let fixedMs = 3000.0
    /// Lines of medium-size text that fit the height, like the site's player.
    static let lines = 11.0

    private struct Slot {
        var lane: Int
        var width: CGFloat
    }

    private var size: CGSize = .zero
    private var layoutKey = ""
    private var scrollDuration = DanmakuLayout.scrollMs
    private var slots: [String: Slot] = [:]
    /// Last scrolling comment per lane: start time and width.
    private var scrollLanes: [Int: (start: Double, width: CGFloat)] = [:]
    /// Start time of the last fixed comment per lane.
    private var topLanes: [Int: Double] = [:]
    private var bottomLanes: [Int: Double] = [:]

    func draw(
        in context: inout GraphicsContext, size: CGSize, timeMs now: Double,
        comments: [NicoComment], counts: [String: Int], translations: [String: String], settings: DanmakuSettings
    ) {
        guard size.width > 0, size.height > 0, !comments.isEmpty else { return }
        let scrollMs = Self.scrollMs / max(settings.speed, 0.1)
        let layoutKey = "\(size.width)x\(size.height)|\(settings.area)|\(scrollMs)"
        if layoutKey != self.layoutKey {
            self.layoutKey = layoutKey
            self.size = size
            self.scrollDuration = scrollMs
            slots = [:]
            scrollLanes = [:]
            topLanes = [:]
            bottomLanes = [:]
        }
        let lineHeight = size.height / Self.lines
        // 显示区域: only the top part of the picture gets lanes.
        let laneCount = max(1, Int((Self.lines * settings.area).rounded(.down)))
        let baseFont = max(10, lineHeight * 0.8 * settings.scale)

        // First comment that can still be on screen (comments are sorted by time).
        var low = 0, high = comments.count
        while low < high {
            let mid = (low + high) / 2
            if Double(comments[mid].vposMs) < now - scrollMs { low = mid + 1 } else { high = mid }
        }

        var shadowed = context
        if settings.stroke == .shadow {
            shadowed.addFilter(.shadow(color: .black.opacity(0.85), radius: 1.2))
        }
        let unbounded = CGSize(width: CGFloat.infinity, height: CGFloat.infinity)
        /// Draws text with the chosen edge: a dark copy around it for 描边.
        func drawText(_ string: String, size fontSize: CGFloat, weight: Font.Weight, color: Color, at point: CGPoint) {
            let font = Font.system(size: fontSize, weight: weight)
            if settings.stroke == .outline {
                let edge = context.resolve(Text(string).font(font).foregroundStyle(.black.opacity(0.85)))
                for (dx, dy) in [(-1.0, 0.0), (1.0, 0.0), (0.0, -1.0), (0.0, 1.0)] {
                    shadowed.draw(edge, at: CGPoint(x: point.x + dx, y: point.y + dy), anchor: .topLeading)
                }
            }
            shadowed.draw(context.resolve(Text(string).font(font).foregroundStyle(color)), at: point, anchor: .topLeading)
        }
        var drawn = 0
        var index = low
        while index < comments.count, drawn < settings.maxOnScreen {
            let comment = comments[index]
            index += 1
            let start = Double(comment.vposMs)
            if start > now { break }
            let duration = comment.position == .scroll ? scrollMs : Self.fixedMs
            let elapsed = now - start
            guard elapsed < duration else { continue }

            let scale: CGFloat = switch comment.size {
            case .big: 1.4
            case .small: 0.7
            case .medium: 1
            }
            let color = Color(rgb: comment.color)
            let body = counts[comment.id].map { "\(comment.body) ×\($0)" } ?? comment.body
            let fontSize = baseFont * scale
            let textSize = context.resolve(Text(body).font(.system(size: fontSize, weight: .bold))).measure(in: unbounded)
            let translation = comment.position == .scroll ? nil : translations[comment.id]
            let slot = slots[comment.id]
                ?? place(comment, width: textSize.width, start: start, laneCount: laneCount, span: translation == nil ? 1 : 2)

            switch comment.position {
            case .scroll:
                let x = size.width - CGFloat(elapsed / duration) * (size.width + textSize.width)
                let y = CGFloat(slot.lane) * lineHeight + (lineHeight - textSize.height) / 2
                drawText(body, size: fontSize, weight: .bold, color: color, at: CGPoint(x: x, y: y))
            case .top, .bottom:
                let isTop = comment.position == .top
                let y = isTop
                    ? CGFloat(slot.lane) * lineHeight + (lineHeight - textSize.height) / 2
                    : CGFloat(laneCount) * lineHeight - CGFloat(slot.lane + 1) * lineHeight + (lineHeight - textSize.height) / 2
                drawText(body, size: fontSize, weight: .bold, color: color,
                         at: CGPoint(x: (size.width - textSize.width) / 2, y: y))
                if let translation {
                    // Local only: the translation on the next line inward, slightly smaller.
                    let translatedFont = baseFont * 0.85
                    let translatedSize = context.resolve(Text(translation).font(.system(size: translatedFont, weight: .semibold)))
                        .measure(in: CGSize(width: size.width, height: CGFloat.infinity))
                    let lineY = isTop ? y + lineHeight : y - lineHeight
                    drawText(translation, size: translatedFont, weight: .semibold, color: color,
                             at: CGPoint(x: (size.width - translatedSize.width) / 2, y: lineY))
                }
            }
            drawn += 1
        }
    }

    /// Picks a line for a comment that just appeared. Scrolling comments take the first line
    /// where they neither touch the previous one as they enter nor catch up with it before it
    /// leaves; with no free line they overlap, as on the site. Fixed comments with a
    /// translation take `span` consecutive lines.
    private func place(_ comment: NicoComment, width: CGFloat, start: Double, laneCount: Int, span: Int) -> Slot {
        var lane: Int?
        switch comment.position {
        case .scroll:
            let travel = Double(size.width)
            let speed = (travel + Double(width)) / scrollDuration
            for candidate in 0..<laneCount {
                guard let last = scrollLanes[candidate], last.start <= start else { lane = candidate; break }
                let lastSpeed = (travel + Double(last.width)) / scrollDuration
                let entered = lastSpeed * (start - last.start) >= Double(last.width) + 8
                let wontCatchUp = speed * (last.start + scrollDuration - start) <= travel
                if entered && wontCatchUp { lane = candidate; break }
            }
            let chosen = lane ?? comment.number % laneCount
            scrollLanes[chosen] = (start, width)
            lane = chosen
        case .top, .bottom:
            var lanes = comment.position == .top ? topLanes : bottomLanes
            func isFree(_ candidate: Int) -> Bool {
                guard let last = lanes[candidate], last <= start else { return true }
                return start - last >= Self.fixedMs
            }
            lane = (0...max(0, laneCount - span)).first { first in (first..<first + span).allSatisfy(isFree) }
            let chosen = lane ?? comment.number % max(1, laneCount - span + 1)
            for taken in chosen..<min(laneCount, chosen + span) { lanes[taken] = start }
            if comment.position == .top { topLanes = lanes } else { bottomLanes = lanes }
            lane = chosen
        }
        let slot = Slot(lane: lane ?? 0, width: width)
        slots[comment.id] = slot
        return slot
    }
}

extension Color {
    /// From 0xRRGGBB.
    init(rgb: UInt32) {
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
