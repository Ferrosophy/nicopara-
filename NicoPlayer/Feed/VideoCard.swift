import NicoKit
import SwiftUI

/// Two-column feed card: thumbnail with play count and duration, title, uploader, reason.
struct VideoCard: View {
    let video: VideoSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.secondary.opacity(0.15)
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay {
                    CoverImage(url: video.thumbnailURL)
                }
                .overlay(alignment: .bottom) {
                    HStack {
                        StatLabel(icon: "play.rectangle", value: Self.compact(video.counts.view))
                        Spacer()
                        Text(Self.duration(video.duration))
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(.linearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                }
                .overlay(alignment: .topLeading) {
                    if video.isPaymentRequired {
                        Text("付费")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.orange, in: .rect(cornerRadius: 4))
                            .padding(5)
                    }
                }
                .clipShape(.rect(cornerRadius: 8))

            Text(video.title)
                .font(.subheadline)
                .lineLimit(2, reservesSpace: true)

            HStack(spacing: 4) {
                if let tag = video.reasonTag {
                    Text("#\(tag)")
                        .foregroundStyle(.tint)
                        .lineLimit(1)
                }
                Text(video.ownerName ?? "")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .font(.caption)
        }
        .contentShape(.rect)
    }

    /// 12345 → "1.2万", like Chinese video sites.
    static func compact(_ count: Int) -> String {
        if Localization.language == .english {
            if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
            if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
            return String(count)
        }
        if count >= 100_000_000 {
            return String(format: Localization.language == .japanese ? "%.1f億" : "%.1f亿", Double(count) / 100_000_000)
        }
        if count >= 10_000 { return String(format: "%.1f万", Double(count) / 10_000) }
        return String(count)
    }

    static func duration(_ seconds: Int) -> String {
        let format: Duration.TimeFormatStyle.Pattern = seconds >= 3600 ? .hourMinuteSecond : .minuteSecond
        return Duration.seconds(seconds).formatted(.time(pattern: format))
    }
}
