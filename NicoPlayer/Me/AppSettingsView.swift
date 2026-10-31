import NicoKit
import SwiftUI

/// 应用设置.
struct AppSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(TranslationStore.self) private var translator
    @State private var cleared = false

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("外观") {
                Picker("语言", selection: $settings.language) {
                    ForEach(AppLanguage.allCases, id: \.self) { Text(verbatim: $0.name).tag($0) }
                }
                AccentPicker()
            }

            Section("弹幕") {
                NavigationLink("弹幕设置") {
                    DanmakuSettingsForm()
                        .navigationTitle("弹幕设置")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }

            Section("播放") {
                Toggle("打开视频自动播放", isOn: $settings.autoplay)
                Toggle("播完自动播放下一个", isOn: $settings.autoplayNext)
                Toggle("循环播放", isOn: $settings.loopPlayback)
                Toggle("回到桌面自动画中画", isOn: $settings.autoPictureInPicture)
                Picker("长按倍速", selection: $settings.boostRate) {
                    Text(verbatim: "2x").tag(2.0)
                    Text(verbatim: "3x").tag(3.0)
                }
                Picker("默认画质", selection: $settings.defaultVideoQuality) {
                    Text("自动").tag("auto")
                    ForEach(["1080", "720", "480", "360", "144"], id: \.self) { Text(verbatim: "\($0)p").tag($0) }
                }
                Picker("默认音质", selection: $settings.defaultAudioQuality) {
                    Text("自动").tag("auto")
                    Text("最高").tag("high")
                    Text("最低").tag("low")
                }
            }

            Section("翻译") {
                Toggle("沉浸式翻译", isOn: $settings.translationEnabled)
                Picker("翻译成", selection: $settings.translationTarget) {
                    ForEach(AppSettings.targets, id: \.code) { Text(verbatim: $0.name).tag($0.code) }
                }
            }

            Section {
                Button(cleared ? "已清除" : "清除缓存") {
                    translator.clear()
                    URLCache.shared.removeAllCachedResponses()
                    cleared = true
                }
                .disabled(cleared)
                LabeledContent("版本") { Text(verbatim: Self.version) }
            }
        }
        .navigationTitle("应用设置")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}

/// 强调色: preset swatches plus a free colour picker.
private struct AccentPicker: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("强调色")
            HStack(spacing: 10) {
                ForEach(AppSettings.accentPresets, id: \.self) { hex in
                    Button {
                        settings.accentHex = hex
                    } label: {
                        Circle()
                            .fill(Color(hex: hex) ?? .blue)
                            .frame(width: 26, height: 26)
                            .overlay {
                                if settings.accentHex.uppercased() == hex.uppercased() {
                                    Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
                ColorPicker("", selection: Binding(
                    get: { settings.accentColor },
                    set: { settings.accentHex = $0.hexString }
                ), supportsOpacity: false)
                .labelsHidden()
            }
        }
        .padding(.vertical, 4)
    }
}

/// 弹幕设置, shared by 应用设置 and the player's ⚙ menu (one set of settings).
struct DanmakuSettingsForm: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("显示") {
                Toggle("显示弹幕", isOn: $settings.danmakuEnabled)
                percentSlider("不透明度", value: $settings.danmakuOpacity, in: 0.2...1, step: 0.05)
                percentSlider("字体大小", value: $settings.danmakuScale, in: 0.5...2, step: 0.05)
                percentSlider("显示区域", value: $settings.danmakuArea, in: 0.25...1, step: 0.25)
                percentSlider("弹幕速度", value: $settings.danmakuSpeed, in: 0.5...2, step: 0.05)
                Picker("同屏数量", selection: $settings.danmakuMaxOnScreen) {
                    Text(verbatim: "20").tag(20)
                    Text(verbatim: "40").tag(40)
                    Text(verbatim: "80").tag(80)
                    Text("无上限").tag(500)
                }
                Picker("描边样式", selection: $settings.danmakuStroke) {
                    Text("阴影").tag(DanmakuSettings.Stroke.shadow)
                    Text("描边").tag(DanmakuSettings.Stroke.outline)
                    Text("无").tag(DanmakuSettings.Stroke.none)
                }
            }

            Section("屏蔽") {
                Toggle("固定弹幕", isOn: $settings.hideFixed)
                Toggle("滚动弹幕", isOn: $settings.hideScrolling)
                Toggle("简易弹幕", isOn: $settings.hideEasy)
                Toggle("UP 主弹幕", isOn: $settings.hideOwner)
                Toggle("合并重复弹幕", isOn: $settings.mergeDuplicates)
                if settings.mergeDuplicates {
                    Toggle("显示次数 ×N", isOn: $settings.countDuplicates)
                }
                Picker("过滤等级", selection: $settings.ngLevel) {
                    Text("无").tag(NGLevel.none)
                    Text("弱").tag(NGLevel.weak)
                    Text("中").tag(NGLevel.medium)
                    Text("强").tag(NGLevel.strong)
                }
                Toggle("同步账号屏蔽设置", isOn: $settings.syncAccountNG)
            }
        }
    }

    private func percentSlider(_ title: LocalizedStringKey, value: Binding<Double>, in range: ClosedRange<Double>,
                               step: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(verbatim: "\(Int((value.wrappedValue * 100).rounded()))%")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: step)
        }
    }
}
