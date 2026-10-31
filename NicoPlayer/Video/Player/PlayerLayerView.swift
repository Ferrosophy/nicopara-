import AVFoundation
import SwiftUI
import UIKit

/// The video picture only: an `AVPlayerLayer`, no controls. Also where picture in picture
/// attaches, since iOS needs the on-screen layer for it.
struct PlayerLayerView: UIViewRepresentable {
    let model: PlayerModel
    var autoPictureInPicture = true

    final class LayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.backgroundColor = .black
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = model.player
        model.attach(view.playerLayer, startsAutomatically: autoPictureInPicture)
        return view
    }

    func updateUIView(_ view: LayerView, context: Context) {
        if view.playerLayer.player !== model.player { view.playerLayer.player = model.player }
        model.attach(view.playerLayer, startsAutomatically: autoPictureInPicture)
    }

    func makeCoordinator() -> PlayerModel { model }

    static func dismantleUIView(_ view: LayerView, coordinator model: PlayerModel) {
        model.detach(view.playerLayer)
    }
}

/// Touch handling on top of the video, with UIKit recognizers so the gestures don't fight:
/// single tap (shows / hides controls, waits for a double tap to fail), double tap
/// (play / pause), long press (speed-up while held), and pan: horizontal seeks, vertical
/// adjusts brightness (left half) / volume (right half).
struct GestureSurface: UIViewRepresentable {
    enum PanKind { case seek, brightness, volume }

    struct PanUpdate {
        var kind: PanKind
        /// Travel since the pan began, as a fraction of the view's width (seek, right is +)
        /// or height (brightness / volume, up is +). nil when the pan ended.
        var progress: Double?
    }

    var onSingleTap: () -> Void
    var onDoubleTap: () -> Void
    var onLongPress: (_ began: Bool) -> Void
    var onPan: (PanUpdate) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let coordinator = context.coordinator

        let doubleTap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.doubleTapped))
        doubleTap.numberOfTapsRequired = 2
        let singleTap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.singleTapped))
        singleTap.require(toFail: doubleTap)
        let longPress = UILongPressGestureRecognizer(target: coordinator, action: #selector(Coordinator.longPressed(_:)))
        longPress.minimumPressDuration = 0.4
        let pan = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.panned(_:)))
        pan.maximumNumberOfTouches = 1
        // A press that turns into a speed-up must not also seek or adjust.
        pan.require(toFail: longPress)

        [doubleTap, singleTap, longPress, pan].forEach(view.addGestureRecognizer)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.surface = self
    }

    @MainActor
    final class Coordinator: NSObject {
        var surface: GestureSurface?
        private var kind: PanKind = .seek

        @objc func singleTapped() { surface?.onSingleTap() }
        @objc func doubleTapped() { surface?.onDoubleTap() }

        @objc func longPressed(_ recognizer: UILongPressGestureRecognizer) {
            switch recognizer.state {
            case .began: surface?.onLongPress(true)
            case .ended, .cancelled, .failed: surface?.onLongPress(false)
            default: break
            }
        }

        @objc func panned(_ recognizer: UIPanGestureRecognizer) {
            guard let view = recognizer.view, view.bounds.width > 0, view.bounds.height > 0 else { return }
            let translation = recognizer.translation(in: view)
            switch recognizer.state {
            case .began:
                let velocity = recognizer.velocity(in: view)
                if abs(velocity.x) >= abs(velocity.y) {
                    kind = .seek
                } else {
                    kind = recognizer.location(in: view).x < view.bounds.midX ? .brightness : .volume
                }
                surface?.onPan(PanUpdate(kind: kind, progress: 0))
            case .changed:
                let progress = kind == .seek
                    ? translation.x / view.bounds.width
                    : -translation.y / view.bounds.height
                surface?.onPan(PanUpdate(kind: kind, progress: progress))
            default:
                surface?.onPan(PanUpdate(kind: kind, progress: nil))
            }
        }
    }
}
