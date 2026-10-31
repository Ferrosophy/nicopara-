import AVFoundation
import MediaPlayer
import SwiftUI
import UIKit

/// Screen brightness of the scene the app runs in.
@MainActor
enum ScreenBrightness {
    private static var screen: UIScreen? {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first
    }

    static var value: Double {
        get { Double(screen?.brightness ?? 0.5) }
        set { screen?.brightness = CGFloat(min(max(newValue, 0), 1)) }
    }
}

/// System volume. iOS has no public setter, so this does what video apps (Bilibili included) do:
/// drive the slider inside an `MPVolumeView`. That view must be on screen (see
/// ``HiddenVolumeView``), which also keeps the system volume popup from covering the video.
@MainActor
final class SystemVolume {
    static let shared = SystemVolume()

    fileprivate weak var slider: UISlider?

    var value: Double { Double(AVAudioSession.sharedInstance().outputVolume) }

    /// Returns false if the volume slider is not available (then nothing changed).
    @discardableResult
    func set(_ newValue: Double) -> Bool {
        guard let slider else { return false }
        slider.value = Float(min(max(newValue, 0), 1))
        slider.sendActions(for: .valueChanged)
        return true
    }
}

/// An `MPVolumeView` that is in the view tree but practically invisible. Hidden or alpha 0
/// would make iOS show its own volume popup again, so it is tiny and nearly transparent.
struct HiddenVolumeView: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: CGRect(x: -100, y: -100, width: 1, height: 1))
        view.alpha = 0.01
        view.isUserInteractionEnabled = false
        SystemVolume.shared.slider = view.subviews.compactMap { $0 as? UISlider }.first
        return view
    }

    func updateUIView(_ view: MPVolumeView, context: Context) {
        if SystemVolume.shared.slider == nil {
            SystemVolume.shared.slider = view.subviews.compactMap { $0 as? UISlider }.first
        }
    }
}

/// Which orientations the app allows right now: portrait normally, landscape in fullscreen.
@MainActor
enum OrientationLock {
    static var mask: UIInterfaceOrientationMask = .portrait

    static func set(_ newMask: UIInterfaceOrientationMask) {
        mask = newMask
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: newMask)) { _ in }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}

/// The video page hides the navigation bar, which normally also turns off swipe-from-the-edge
/// to go back. Keep it on whenever there is a page to go back to.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1 && NavigationSwipe.isEnabled
    }
}

/// Off while the player is fullscreen, so an edge swipe in landscape doesn't leave the page.
@MainActor
enum NavigationSwipe {
    static var isEnabled = true
}
