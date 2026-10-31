import Foundation
import NicoKit

// Chinese labels for the site's search options; the site's Japanese label is in the comment.

extension SearchQuery.SortKey {
    var chineseLabel: String {
        switch self {
        case .hotLikeAndMylist: "人气"          // ニコニコで人気
        case .personalized: "为你推荐"          // あなたへのおすすめ
        case .registeredAt: "投稿时间"          // 投稿日時
        case .viewCount: "播放数"               // 再生数
        case .lastCommentTime: "最新评论时间"    // コメント日時
        case .likeCount: "点赞数"               // いいね！数
        case .commentCount: "评论数"            // コメント数
        case .mylistCount: "收藏数"             // マイリスト登録数
        case .duration: "时长"                  // 再生時間
        }
    }
}

extension SearchQuery.SortOrder {
    var chineseLabel: String {
        switch self {
        case .desc: "降序"  // 降順
        case .asc: "升序"   // 昇順
        }
    }

    var systemImage: String { self == .desc ? "arrow.down" : "arrow.up" }
}

extension SearchQuery.Kind {
    var chineseLabel: String {
        switch self {
        case .any: "不限"        // 指定なし
        case .user: "用户投稿"   // ユーザー
        case .channel: "频道"    // チャンネル
        }
    }
}

extension SearchQuery.LengthRange {
    var chineseLabel: String {
        switch self {
        case .any: "不限"
        case .under5Minutes: "5 分钟以内"
        case .over20Minutes: "20 分钟以上"
        }
    }
}

extension SearchQuery.PostedRange {
    var chineseLabel: String {
        switch self {
        case .any: "不限"
        case .hour: "1 小时内"
        case .day: "24 小时内"
        case .week: "1 周内"
        case .month: "1 个月内"
        case .year: "1 年内"
        }
    }
}

extension SearchQuery.Genre {
    var chineseLabel: String {
        switch self {
        case .all: "不限"
        case .entertainment: "娱乐"                 // エンターテイメント
        case .radio: "电台"                          // ラジオ
        case .musicSound: "音乐・声音"               // 音楽・サウンド
        case .dance: "舞蹈"                          // ダンス
        case .animal: "动物"                         // 動物
        case .nature: "自然"                         // 自然
        case .cooking: "料理"                        // 料理
        case .travelingOutdoor: "旅行・户外"         // 旅行・アウトドア
        case .vehicle: "交通工具"                    // 乗り物
        case .sports: "体育"                         // スポーツ
        case .societyPoliticsNews: "社会・政治・时事" // 社会・政治・時事
        case .technologyCraft: "技术・手工"          // 技術・工作
        case .commentaryLecture: "解说・讲座"        // 解説・講座
        case .anime: "动画"                          // アニメ
        case .game: "游戏"                           // ゲーム
        case .other: "其他"                          // その他
        case .r18: "例のソレ"                         // 例のソレ (site's own name, kept as is)
        }
    }
}

extension SearchQuery.Mode {
    var chineseLabel: String { self == .keyword ? "关键词" : "标签" }
}

extension SearchQuery.Genre {
    var label: String { L(chineseLabel) }
}

extension SearchQuery.Kind {
    var label: String { L(chineseLabel) }
}

extension SearchQuery.LengthRange {
    var label: String { L(chineseLabel) }
}

extension SearchQuery.Mode {
    var label: String { L(chineseLabel) }
}

extension SearchQuery.PostedRange {
    var label: String { L(chineseLabel) }
}

extension SearchQuery.SortKey {
    var label: String { L(chineseLabel) }
}

extension SearchQuery.SortOrder {
    var label: String { L(chineseLabel) }
}
