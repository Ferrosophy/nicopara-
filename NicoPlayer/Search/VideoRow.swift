import NicoKit
import SwiftUI

/// Search result row: thumbnail on the left, title and stats on the right.
struct VideoRow: View {
    let video: VideoSummary

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Color.secondary.opacity(0.15)
                .frame(width: 132)
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay {
                    CoverImage(url: video.thumbnailURL)
                }
                .overlay(alignment: .bottomTrailing) {
                    Text(VideoCard.duration(video.duration))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.black.opacity(0.6), in: .rect(cornerRadius: 3))
                        .padding(4)
                }
                .clipShape(.rect(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(.subheadline)
                    .lineLimit(2)
                Text(ownerAndDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                // One line that may shrink, never wider than the row (a forced width made long
                // numbers push whole rows sideways in the ranking).
                HStack(spacing: 10) {
                    StatLabel(icon: "play.rectangle", value: VideoCard.compact(video.counts.view))
                    StatLabel(icon: "text.bubble", value: VideoCard.compact(video.counts.comment))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

                if video.isPaymentRequired {
                    Text("付费").font(.caption2.bold()).foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// "惑井 · 2026/8/21", one line.
    private var ownerAndDate: String {
        [video.ownerName, video.registeredAt?.formatted(date: .numeric, time: .omitted)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

/// Icon and number with no gap between them.
struct StatLabel: View {
    let icon: String
    let value: String

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
            Text(verbatim: value)
        }
    }
}
