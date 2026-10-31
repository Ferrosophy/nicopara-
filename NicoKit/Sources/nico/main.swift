import Foundation
import NicoKit

// Usage: swift run nico <video URL or ID>
//        swift run nico me
// Set NICO_USER_SESSION to a user_session cookie value to act as that user.
let arguments = CommandLine.arguments.dropFirst()
let client = NicoClient(userSession: ProcessInfo.processInfo.environment["NICO_USER_SESSION"])

if arguments.first == "me" {
    do {
        let account = try await client.me()
        print("\(account.nickname)（ID \(account.id)）\(account.isPremium ? "高级会员" : "普通会员")")
    } catch {
        print("失败：\(error.localizedDescription)")
        exit(1)
    }
    exit(0)
}

if arguments.first == "recommend" {
    do {
        let batch = try await client.recommendations(limit: 20)
        for video in batch.videos {
            let reason = video.reasonTag.map { "  #\($0)" } ?? ""
            print("\(video.id)\t\(video.counts.view) 播放\t\(video.title)\(reason)")
        }
    } catch {
        print("失败：\(error.localizedDescription)")
        exit(1)
    }
    exit(0)
}

guard let input = arguments.first, let id = VideoID(parsing: input) else {
    print("用法：nico <视频链接或编号>，例如 nico sm9；nico me 查看登录账号")
    exit(2)
}

do {
    let info = try await client.videoInfo(id)
    let date = info.registeredAt.map { $0.formatted(date: .numeric, time: .shortened) } ?? "?"
    print("""
    编号：\(info.id)
    标题：\(info.title)
    投稿者：\(info.uploader?.name ?? "?")
    投稿时间：\(date)
    时长：\(info.duration / 60) 分 \(info.duration % 60) 秒
    播放 \(info.counts.view) · 弹幕 \(info.counts.comment) · 收藏 \(info.counts.mylist) · 赞 \(info.counts.like)
    观看权限：\(info.access.rawValue)
    封面：\(info.thumbnailURL?.absoluteString ?? "-")
    标签：\(info.tags.joined(separator: "、"))
    画质：\(info.videoStreams.filter(\.isAvailable).compactMap(\.label).joined(separator: " / "))
    简介：
    \(info.descriptionText)
    """)
} catch {
    print("失败：\(error.localizedDescription)")
    exit(1)
}
