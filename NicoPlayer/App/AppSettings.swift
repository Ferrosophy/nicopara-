import Foundation
import NicoKit
import Observation
import SwiftUI

/// 应用设置, saved in UserDefaults. Each property writes itself back on change.
@MainActor @Observable
final class AppSettings {
    private let defaults = UserDefaults.standard

    // MARK: 弹幕 · 显示
    var danmakuEnabled: Bool { didSet { save(danmakuEnabled, "danmakuEnabled") } }
    var danmakuOpacity: Double { didSet { save(danmakuOpacity, "danmakuOpacity") } }
    /// Font size, 0.5–2.0.
    var danmakuScale: Double { didSet { save(danmakuScale, "danmakuScale") } }
    /// Fraction of the picture height danmaku may use: 0.25 / 0.5 / 0.75 / 1.
    var danmakuArea: Double { didSet { save(danmakuArea, "danmakuArea") } }
    /// Scroll speed, 0.5–2.0 (1 = the site's 4 seconds across).
    var danmakuSpeed: Double { didSet { save(danmakuSpeed, "danmakuSpeed") } }
    var danmakuMaxOnScreen: Int { didSet { save(danmakuMaxOnScreen, "danmakuMaxOnScreen") } }
    var danmakuStroke: DanmakuSettings.Stroke { didSet { save(danmakuStroke.rawValue, "danmakuStroke") } }

    // MARK: 弹幕 · 屏蔽
    var hideFixed: Bool { didSet { save(hideFixed, "hideFixed") } }
    var hideScrolling: Bool { didSet { save(hideScrolling, "hideScrolling") } }
    var hideEasy: Bool { didSet { save(hideEasy, "hideEasy") } }
    var hideOwner: Bool { didSet { save(hideOwner, "hideOwner") } }
    var mergeDuplicates: Bool { didSet { save(mergeDuplicates, "mergeDuplicates") } }
    var countDuplicates: Bool { didSet { save(countDuplicates, "countDuplicates") } }
    var ngLevel: NGLevel { didSet { save(ngLevel.rawValue, "ngLevel") } }
    var syncAccountNG: Bool { didSet { save(syncAccountNG, "syncAccountNG") } }

    // MARK: 播放
    var autoplay: Bool { didSet { save(autoplay, "autoplay") } }
    var boostRate: Double { didSet { save(boostRate, "boostRate") } }
    var loopPlayback: Bool { didSet { save(loopPlayback, "loopPlayback") } }
    var autoplayNext: Bool { didSet { save(autoplayNext, "autoplayNext") } }
    var autoPictureInPicture: Bool { didSet { save(autoPictureInPicture, "autoPictureInPicture") } }
    /// "auto", or a height like "720".
    var defaultVideoQuality: String { didSet { save(defaultVideoQuality, "defaultVideoQuality") } }
    /// "auto", "high" or "low".
    var defaultAudioQuality: String { didSet { save(defaultAudioQuality, "defaultAudioQuality") } }

    // MARK: 翻译
    var translationEnabled: Bool { didSet { save(translationEnabled, "translationEnabled") } }
    var translationTarget: String { didSet { save(translationTarget, "translationTarget") } }

    // MARK: 外观
    /// "#RRGGBB".
    var accentHex: String { didSet { save(accentHex, "accentHex") } }
    var language: AppLanguage {
        didSet {
            save(language.rawValue, "language")
            Localization.language = language
        }
    }

    /// Read before the settings object exists (to install the language at launch).
    static var storedLanguage: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: "language") ?? "") ?? .chinese
    }

    /// Languages offered for translation (Google codes).
    static let targets: [(code: String, name: String)] = [
        ("zh-CN", "简体中文"), ("zh-TW", "繁體中文"), ("en", "English"), ("ko", "한국어"),
    ]

    static let accentPresets: [String] = ["#0A84FF", "#FB7299", "#FF9500", "#34C759", "#AF52DE", "#FF3B30", "#5AC8FA", "#8E8E93"]

    init() {
        defaults.register(defaults: [
            "danmakuEnabled": true, "danmakuOpacity": 0.92, "danmakuScale": 1.0, "danmakuArea": 1.0,
            "danmakuSpeed": 1.0, "danmakuMaxOnScreen": 80, "danmakuStroke": "shadow",
            "hideFixed": false, "hideScrolling": false, "hideEasy": false, "hideOwner": false,
            "mergeDuplicates": false, "countDuplicates": true, "ngLevel": "medium", "syncAccountNG": true,
            "autoplay": true, "boostRate": 2.0, "loopPlayback": false, "autoplayNext": false, "autoPictureInPicture": true,
            "defaultVideoQuality": "auto", "defaultAudioQuality": "auto",
            "translationEnabled": true, "translationTarget": "zh-CN",
            "accentHex": "#0A84FF", "language": "zh-Hans",
        ])
        danmakuEnabled = defaults.bool(forKey: "danmakuEnabled")
        danmakuOpacity = defaults.double(forKey: "danmakuOpacity")
        danmakuScale = defaults.double(forKey: "danmakuScale")
        danmakuArea = defaults.double(forKey: "danmakuArea")
        danmakuSpeed = defaults.double(forKey: "danmakuSpeed")
        danmakuMaxOnScreen = defaults.integer(forKey: "danmakuMaxOnScreen")
        danmakuStroke = DanmakuSettings.Stroke(rawValue: defaults.string(forKey: "danmakuStroke") ?? "") ?? .shadow
        hideFixed = defaults.bool(forKey: "hideFixed")
        hideScrolling = defaults.bool(forKey: "hideScrolling")
        hideEasy = defaults.bool(forKey: "hideEasy")
        hideOwner = defaults.bool(forKey: "hideOwner")
        mergeDuplicates = defaults.bool(forKey: "mergeDuplicates")
        countDuplicates = defaults.bool(forKey: "countDuplicates")
        ngLevel = NGLevel(rawValue: defaults.string(forKey: "ngLevel") ?? "") ?? .medium
        syncAccountNG = defaults.bool(forKey: "syncAccountNG")
        autoplay = defaults.bool(forKey: "autoplay")
        boostRate = defaults.double(forKey: "boostRate")
        loopPlayback = defaults.bool(forKey: "loopPlayback")
        autoplayNext = defaults.bool(forKey: "autoplayNext")
        autoPictureInPicture = defaults.bool(forKey: "autoPictureInPicture")
        defaultVideoQuality = defaults.string(forKey: "defaultVideoQuality") ?? "auto"
        defaultAudioQuality = defaults.string(forKey: "defaultAudioQuality") ?? "auto"
        translationEnabled = defaults.bool(forKey: "translationEnabled")
        translationTarget = defaults.string(forKey: "translationTarget") ?? "zh-CN"
        accentHex = defaults.string(forKey: "accentHex") ?? "#0A84FF"
        language = AppLanguage(rawValue: defaults.string(forKey: "language") ?? "") ?? .chinese
    }

    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }

    var danmaku: DanmakuSettings {
        DanmakuSettings(opacity: danmakuOpacity, scale: danmakuScale, maxOnScreen: danmakuMaxOnScreen,
                        area: danmakuArea, speed: danmakuSpeed, stroke: danmakuStroke)
    }

    var accentColor: Color { Color(hex: accentHex) ?? .blue }

    /// What 屏蔽 hides; `ng` is the account's NG list when syncing.
    func filterOptions(ng: [NGItem]) -> DanmakuFilterOptions {
        var options = DanmakuFilterOptions()
        options.ngLevel = ngLevel
        options.hideEasy = hideEasy
        options.hideOwner = hideOwner
        options.hideFixed = hideFixed
        options.hideScrolling = hideScrolling
        options.mergeDuplicates = mergeDuplicates
        options.countDuplicates = countDuplicates
        options.ng = syncAccountNG ? ng : []
        return options
    }

    /// The streams to ask for first, from 默认画质 / 默认音质.
    func defaultSelection(for info: VideoInfo) -> HLSSelection {
        var selection = HLSSelection()
        if defaultVideoQuality != "auto", let height = Int(defaultVideoQuality) {
            // The best available quality not above the preferred one.
            selection.videoID = info.videoStreams
                .filter { $0.isAvailable && ($0.height ?? 0) <= height }
                .max { ($0.height ?? 0) < ($1.height ?? 0) }?.id
        }
        let audios = info.audioStreams.filter(\.isAvailable).sorted { ($0.bitRate ?? 0) < ($1.bitRate ?? 0) }
        switch defaultAudioQuality {
        case "high": selection.audioID = audios.last?.id
        case "low": selection.audioID = audios.first?.id
        default: break
        }
        return selection
    }
}

enum AppLanguage: String, CaseIterable {
    case chinese = "zh-Hans"
    case english = "en"
    case japanese = "ja"

    var name: String {
        switch self {
        case .chinese: "中文"
        case .english: "English"
        case .japanese: "日本語"
        }
    }
}

extension Color {
    /// From "#RRGGBB".
    init?(hex: String) {
        let digits = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(rgb: value)
    }

    /// "#RRGGBB" in sRGB.
    var hexString: String {
        let resolved = UIColor(self).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func channel(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", channel(red), channel(green), channel(blue))
    }
}
