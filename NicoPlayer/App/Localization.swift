import Foundation
import ObjectiveC

/// In-app language (应用设置 → 语言), switchable without restarting.
///
/// The Chinese text in the code is the key. `Bundle.main` is given a subclass whose
/// `localizedString(forKey:value:table:)` answers from the table below, so SwiftUI's
/// `Text("…")`, `Button("…")` etc. and `String(localized:)` pick up the chosen language; the
/// app redraws itself when the language changes. Keys with a value filled in use the same
/// placeholders SwiftUI generates (`%@` for text, `%lld` for whole numbers).
/// Niconico's own content (titles, tags, uploader names) is never translated.
enum Localization {
    nonisolated(unsafe) static var language: AppLanguage = .chinese

    static func install(_ language: AppLanguage) {
        self.language = language
        object_setClass(Bundle.main, LocalizedBundle.self)
    }

    static func lookup(_ key: String) -> String? {
        switch language {
        case .chinese: nil
        case .english: table[key]?.0
        case .japanese: table[key]?.1
        }
    }

    /// Chinese key → (English, Japanese).
    static let table: [String: (String, String)] = [
        // Tabs and navigation
        "首页": ("Home", "ホーム"), "关注": ("Following", "フォロー"), "我的": ("Me", "マイページ"),
        "推荐": ("For You", "おすすめ"), "分区": ("Genres", "ジャンル"),
        "为你推荐": ("For You", "あなたへのおすすめ"),
        "搜索视频、标签，或粘贴链接": ("Search videos, tags, or paste a link", "動画・タグを検索、またはリンクを貼り付け"),
        "未登录：显示的是通用推荐。登录后是你的个性化推荐。": ("Not logged in: showing general picks. Log in for your own recommendations.", "未ログイン：一般のおすすめを表示中。ログインするとあなた向けのおすすめになります。"),
        "重试": ("Retry", "再試行"),
        "暂时没有更多推荐了，下拉刷新试试": ("No more for now — pull down to refresh", "今はこれ以上ありません。引っ張って更新してください"),
        "返回": ("Back", "戻る"), "回到首页": ("Home", "ホームへ"),

        // Genres / ranking
        "时间": ("Period", "期間"), "全部": ("All", "すべて"),
        "这个时间范围里没有视频": ("No videos in this period", "この期間の動画はありません"),
        "每小时": ("Hourly", "毎時"), "24小时": ("24 hours", "24時間"), "每周": ("Weekly", "週間"), "每月": ("Monthly", "月間"),
        "综合": ("All genres", "総合"), "游戏": ("Games", "ゲーム"), "动画": ("Anime", "アニメ"),
        "VOCALOID": ("VOCALOID", "ボカロ"),
        "合成音声实况・解说・剧场": ("Voice synth commentary & theater", "音声合成実況・解説・劇場"),
        "娱乐": ("Entertainment", "エンタメ"), "音乐": ("Music", "音楽"), "翻唱": ("Song covers", "歌ってみた"),
        "舞蹈": ("Dance", "踊ってみた"), "演奏": ("Performance", "演奏してみた"),
        "解说・讲座": ("Commentary & lectures", "解説・講座"), "料理": ("Cooking", "料理"),
        "旅行・户外": ("Travel & outdoors", "旅行・アウトドア"), "自然": ("Nature", "自然"),
        "交通工具": ("Vehicles", "乗り物"), "技术・手工": ("Tech & crafts", "技術・工作"),
        "社会・政治・时事": ("Society, politics & news", "社会・政治・時事"), "电台": ("Radio", "ラジオ"),
        "体育": ("Sports", "スポーツ"), "动物": ("Animals", "動物"), "其他": ("Other", "その他"),
        "例のソレ": ("Adult (例のソレ)", "例のソレ"),

        // Lists and cards
        "付费": ("Paid", "有料"),
        "更新列表": ("Updates", "新着"), "关注列表": ("Following", "フォロー中"),
        "关注的 UP 主最近没有投稿": ("No recent uploads from people you follow", "フォロー中の投稿者の新着はありません"),
        "还没有关注任何人": ("You aren't following anyone yet", "まだ誰もフォローしていません"),
        "主页": ("Profile", "ユーザーページ"),
        "%lld 个投稿": ("%lld uploads", "投稿 %lld 件"), "还没有投稿": ("No uploads yet", "まだ投稿がありません"),
        "投稿视频": ("Uploads", "投稿動画"),
        "投稿时间": ("Upload date", "投稿日時"), "新→旧": ("newest first", "新しい順"), "旧→新": ("oldest first", "古い順"),
        "播放数": ("Views", "再生数"), "多→少": ("most first", "多い順"), "少→多": ("fewest first", "少ない順"),
        "最新评论": ("Latest comment", "コメントが新しい"), "评论数": ("Comments", "コメント数"),
        "点赞数": ("Likes", "いいね！数"), "收藏数": ("Mylists", "マイリスト数"), "时长": ("Length", "再生時間"),
        "长→短": ("longest first", "長い順"), "短→长": ("shortest first", "短い順"),

        // 我的
        "稍后观看": ("Watch Later", "あとで見る"), "历史观看": ("History", "視聴履歴"),
        "本地列表": ("Local List", "ローカルリスト"), "账户设置": ("Account Settings", "アカウント設定"),
        "应用设置": ("App Settings", "アプリ設定"), "退出登录": ("Log Out", "ログアウト"), "退出登录？": ("Log out?", "ログアウトしますか？"),
        "高级会员": ("Premium member", "プレミアム会員"), "普通会员": ("Regular member", "一般会員"),
        "正在确认登录状态…": ("Checking login…", "ログイン状態を確認中…"),
        "重新加载账号信息": ("Reload account", "アカウント情報を再読み込み"),
        "未登录": ("Not logged in", "未ログイン"),
        "登录后可看个性化推荐、关注、稍后观看和历史": ("Log in for recommendations, following, Watch Later and history", "ログインするとおすすめ・フォロー・あとで見る・履歴が使えます"),
        "登录 Niconico": ("Log in to Niconico", "ニコニコにログイン"), "需要登录": ("Login required", "ログインが必要です"),
        "%@需要登录 Niconico。请到「我的」页面登录。": ("%@ needs a Niconico login. Log in on the Me tab.", "%@にはニコニコへのログインが必要です。「マイページ」からログインしてください。"),
        "共 %lld 个，和 Niconico 账号同步": ("%lld videos, synced with your Niconico account", "%lld 件・ニコニコアカウントと同期"),
        "移出": ("Remove", "削除"),
        "稍后观看是空的。在视频页点「稍后观看」加入。": ("Watch Later is empty. Add videos from a video page.", "あとで見るは空です。動画ページから追加できます。"),
        "看过：%@": ("Watched %@", "視聴：%@"), "还没有观看记录": ("No history yet", "視聴履歴はまだありません"),

        // Local list
        "默认": ("Default", "デフォルト"), "全部 %lld": ("All %lld", "すべて %lld"), "删除": ("Delete", "削除"),
        "移到分组": ("Move to group", "グループへ移動"),
        "本地列表是空的。在视频页点「本地列表」加入。": ("Your local list is empty. Add videos from a video page.", "ローカルリストは空です。動画ページから追加できます。"),
        "没有符合条件的视频": ("No matching videos", "該当する動画はありません"), "搜索标题": ("Search titles", "タイトルを検索"),
        "管理分组": ("Manage groups", "グループを管理"), "导出": ("Export", "書き出し"), "导入": ("Import", "読み込み"),
        "好": ("OK", "OK"), "新建分组": ("New group", "新しいグループ"), "分组名": ("Group name", "グループ名"),
        "添加": ("Add", "追加"), "重命名": ("Rename", "名前を変更"),
        "左滑分组可以重命名或删除；删除分组后，里面的视频会移到「默认」。": ("Swipe a group left to rename or delete it. Deleting moves its videos to Default.", "グループを左にスワイプして名前変更・削除。削除すると動画は「デフォルト」に移ります。"),
        "完成": ("Done", "完了"), "重命名分组": ("Rename group", "グループ名を変更"), "新名字": ("New name", "新しい名前"),
        "取消": ("Cancel", "キャンセル"), "确定": ("OK", "OK"),
        "导出失败：%@": ("Export failed: %@", "書き出しに失敗しました：%@"),
        "导入完成：新增 %lld 个视频（已有的保持不变）": ("Imported: %lld new videos (existing ones kept)", "読み込み完了：%lld 件追加（既存はそのまま）"),
        "导入失败：不是 nicopara 导出的本地列表文件（%@）": ("Import failed: not a nicopara local list file (%@)", "読み込み失敗：nicopara のローカルリストファイルではありません（%@）"),
        "本地列表保存失败：%@": ("Couldn't save the local list: %@", "ローカルリストを保存できませんでした：%@"),

        // App settings
        "外观": ("Appearance", "外観"), "语言": ("Language", "言語"), "强调色": ("Accent color", "アクセントカラー"),
        "弹幕": ("Comments", "コメント"), "弹幕设置": ("Comment Settings", "コメント設定"),
        "播放": ("Playback", "再生"), "打开视频自动播放": ("Autoplay when opening a video", "動画を開いたら自動再生"),
        "播完自动播放下一个": ("Play next automatically", "次の動画を自動再生"), "循环播放": ("Loop", "ループ再生"),
        "回到桌面自动画中画": ("Picture in Picture when leaving the app", "ホームに戻るとピクチャ・イン・ピクチャ"),
        "长按倍速": ("Long-press speed", "長押し倍速"), "默认画质": ("Default quality", "デフォルト画質"),
        "自动": ("Auto", "自動"), "默认音质": ("Default audio quality", "デフォルト音質"),
        "最高": ("Highest", "最高"), "最低": ("Lowest", "最低"),
        "翻译": ("Translation", "翻訳"), "沉浸式翻译": ("Inline translation", "翻訳を表示"),
        "翻译成": ("Translate to", "翻訳先"),
        "已清除": ("Cleared", "削除しました"), "清除缓存": ("Clear cache", "キャッシュを削除"), "版本": ("Version", "バージョン"),
        "翻译失败：%@": ("Translation failed: %@", "翻訳に失敗しました：%@"),

        // Comment settings
        "显示": ("Display", "表示"), "显示弹幕": ("Show comments", "コメントを表示"), "不透明度": ("Opacity", "不透明度"),
        "字体大小": ("Font size", "文字サイズ"), "显示区域": ("Display area", "表示範囲"), "弹幕速度": ("Speed", "速度"),
        "同屏数量": ("Max on screen", "同時表示数"), "无上限": ("Unlimited", "無制限"),
        "描边样式": ("Edge style", "縁取り"), "阴影": ("Shadow", "影"), "描边": ("Outline", "縁取り"), "无": ("None", "なし"),
        "屏蔽": ("Hide", "非表示"), "固定弹幕": ("Fixed (top / bottom)", "固定コメント（上・下）"),
        "滚动弹幕": ("Scrolling", "流れるコメント"),
        "简易弹幕": ("Easy comments", "かんたんコメント"),
        "UP 主弹幕": ("Uploader comments", "投稿者コメント"),
        "开启": ("On", "オン"), "关闭": ("Off", "オフ"),
        "合并重复弹幕": ("Merge duplicates", "重複コメントをまとめる"), "显示次数 ×N": ("Show count ×N", "回数 ×N を表示"),
        "过滤等级": ("Filter level (Shared NG)", "共有NGレベル"), "弱": ("Weak", "弱"), "中": ("Medium", "中"), "强": ("Strong", "強"),
        "同步账号屏蔽设置": ("Use my account's NG settings", "アカウントのNG設定を使う"),

        // Search
        "人气": ("Popular", "ニコニコで人気"), "最新评论时间": ("Latest comment", "コメント日時"),
        "降序": ("Descending", "降順"), "升序": ("Ascending", "昇順"), "不限": ("Any", "指定なし"),
        "用户投稿": ("User uploads", "ユーザー"), "频道": ("Channel", "チャンネル"),
        "5 分钟以内": ("Under 5 min", "5分以内"), "20 分钟以上": ("Over 20 min", "20分以上"),
        "1 小时内": ("Past hour", "1時間以内"), "24 小时内": ("Past 24 hours", "24時間以内"), "1 周内": ("Past week", "1週間以内"),
        "1 个月内": ("Past month", "1ヶ月以内"), "1 年内": ("Past year", "1年以内"), "音乐・声音": ("Music & sound", "音楽・サウンド"),
        "关键词": ("Keyword", "キーワード"), "标签": ("Tag", "タグ"), "搜索类型": ("Search type", "検索の種類"),
        "搜索 Niconico": ("Search Niconico", "ニコニコを検索"),
        "粘贴视频链接或输入 sm 编号可直接打开视频。": ("Paste a video link or type an sm number to open a video.", "動画リンクを貼るか sm 番号を入力すると直接開けます。"),
        "搜索": ("Search", "検索"), "搜索标签": ("Search tags", "タグを検索"), "打开视频 %@": ("Open video %@", "動画 %@ を開く"),
        "输入文字，列出匹配的标签": ("Type to list matching tags", "入力すると一致するタグを表示します"),
        "没有找到结果": ("No results", "見つかりませんでした"), "共 %@ 个结果": ("%@ results", "%@ 件"),
        "排序": ("Sort", "並び替え"), "类型": ("Type", "動画種別"), "类别": ("Genre", "ジャンル"),
        "重置筛选": ("Reset filters", "絞り込みをリセット"), "日期范围": ("Date range", "期間指定"),
        "%@ 起": ("from %@", "%@ から"), "至 %@": ("until %@", "%@ まで"),
        "开始日期": ("Start date", "開始日"), "开始": ("Start", "開始"), "结束日期": ("End date", "終了日"), "结束": ("End", "終了"),
        "按日本时间的投稿日期筛选，和网页版的「開始日 / 終了日」相同。": ("Filters by upload date in Japan time, like the website's start / end date.", "日本時間の投稿日で絞り込みます（Web版の開始日・終了日と同じ）。"),

        // Video page
        "简介": ("Info", "概要"), "弹幕 %@": ("Comments %@", "コメント %@"),
        "最热": ("Top", "人気"), "最新": ("Newest", "新着"), "按时间点": ("By time", "再生位置順"),
        "最热弹幕": ("Top comments", "人気のコメント"), "最新弹幕": ("Newest comments", "新着コメント"),
        "已加载 %lld 条": ("%lld loaded", "%lld 件読み込み済み"), "还没有弹幕": ("No comments yet", "コメントはまだありません"),
        "UP 主": ("Uploader", "投稿者"), "共 %lld 个视频": ("%lld videos", "全 %lld 本"),
        "关闭弹幕": ("Hide comments", "コメントを非表示"), "打开弹幕": ("Show comments", "コメントを表示"),
        "退出全屏": ("Exit fullscreen", "全画面を終了"), "全屏": ("Fullscreen", "全画面"), "画中画": ("Picture in Picture", "ピクチャ・イン・ピクチャ"),
        "倍速": ("Speed", "再生速度"), "正常": ("Normal", "標準"), "画质": ("Quality", "画質"), "音质": ("Audio quality", "音質"),
        "播放设置": ("Playback settings", "再生設定"), "%@x 倍速中": ("%@x speed", "%@倍速再生中"),
        "%@%lld 秒": ("%@%lld s", "%@%lld 秒"), "亮度": ("Brightness", "明るさ"), "音量": ("Volume", "音量"),
        "%@ %lld%%": ("%@ %lld%%", "%@ %lld%%"),
        "已关注": ("Following", "フォロー中"), "%@ 粉丝": ("%@ followers", "フォロワー %@"), "%lld 投稿": ("%lld uploads", "投稿 %lld"),
        "收起": ("Show less", "閉じる"), "展开简介": ("Show more", "続きを表示"), "合集：": ("Series:", "シリーズ："),
        "共 %lld": ("%lld total", "全 %lld"), "相关推荐": ("Related", "関連動画"),
        "仅高级会员可看": ("Premium members only", "プレミアム会員限定"), "仅频道会员可看": ("Channel members only", "チャンネル会員限定"),
        "付费视频": ("Paid video", "有料動画"), "在「%@」里": ("In “%@”", "「%@」にあります"), "移到「%@」": ("Move to “%@”", "「%@」へ移動"),
        "取消收藏": ("Remove from list", "保存を解除"), "收藏到本地列表": ("Save to local list", "ローカルリストに保存"),
        "已收藏": ("Saved", "保存済み"), "收藏": ("Save", "保存"), "已在稍后": ("In Watch Later", "あとで見る済み"), "分享": ("Share", "共有"),
        "点赞失败：%@": ("Couldn't like: %@", "いいね！できませんでした：%@"),
        "关注失败：%@": ("Couldn't follow: %@", "フォローできませんでした：%@"),
        "弹幕加载失败：%@": ("Couldn't load comments: %@", "コメントを読み込めませんでした：%@"),
        "播放失败：%@": ("Playback failed: %@", "再生に失敗しました：%@"),
        "未知错误": ("Unknown error", "不明なエラー"),

        // 听视频
        "听视频": ("Listen", "音声で聴く"), "播放视频": ("Watch video", "動画を再生"), "更换列表": ("Change list", "リストを変更"),
        "正在播放": ("Now Playing", "再生中"), "列表循环": ("Repeat list", "リストをリピート"), "单曲循环": ("Repeat one", "1曲リピート"),
        "随机播放": ("Shuffle", "シャッフル"), "上一首": ("Previous", "前へ"), "下一首": ("Next", "次へ"), "列表": ("List", "リスト"),
        "暂停": ("Pause", "一時停止"), "退出听视频": ("Stop listening", "音声モードを終了"),
    ]
}

/// `Bundle.main`'s class after `Localization.install`.
private final class LocalizedBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        Localization.lookup(key) ?? super.localizedString(forKey: key, value: value, table: tableName)
    }
}

/// The current language's text for a Chinese key held in a `String` (SwiftUI only localizes
/// literals by itself).
func L(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: key, table: nil)
}
