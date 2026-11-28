import AppKit
import PostureCore
import SwiftUI

enum BubbleLayout {
    // Without the long neck, the head is taken to be this many turtle sizes above the feet
    static let headAbove: CGFloat = 0.8
    // Room between the head and the tip of the bubble's tail, in points
    static let headGap: CGFloat = 8
    // A recovery is celebrated only this soon after it was detected, in seconds
    static let recoverFresh: TimeInterval = 5
    // The timer sits this far from the bottom right corner while the turtle is hidden, in points
    static let cornerInset: CGFloat = 24
    static let cornerSize = CGSize(width: 200, height: 80)
}

// Clicks fall through to the turtle view, where TurtlePointer decides
private final class HeadHost: NSHostingView<HeadView> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// Picks speech bubbles from detection, posture and the study timer, and keeps the bubble, or else the running timer,
// over the turtle's head. Runs from the overlay's update loop; the per-frame follower exists only while something is shown
final class TurtleBubbles {
    private let monitor: PostureMonitor
    private let timer: StudyTimer
    private var picker = BubblePicker(cooldowns: BubbleTiming.cooldowns.mapValues { $0 * FastTimers.scale })
    private var detecting = false
    private var stretchAt: TimeInterval = 0
    private var seenExit: Int?
    private var timerPhase: PomodoroPhase?
    private var content: HeadContent?
    private var host: HeadHost?
    private weak var container: NSView?
    private weak var view: TurtleView?
    private weak var pointer: TurtlePointer?

    init(monitor: PostureMonitor, timer: StudyTimer) {
        self.monitor = monitor
        self.timer = timer
    }

    func attach(container: NSView, view: TurtleView, pointer: TurtlePointer) {
        self.container = container
        self.view = view
        self.pointer = pointer
        // An exit that happened before the overlay was shown is not celebrated
        seenExit = monitor.feedback.lastExit?.id
    }

    // The overlay closed: nothing is queued or shown, and detection counts as started again next time
    func detach() {
        show(nil)
        picker.reset()
        detecting = false
        container = nil
        view = nil
        pointer = nil
    }

    func update(stretchReminder: Bool) {
        let now = FaceCapture.now()
        if monitor.isDetecting != detecting {
            detecting = monitor.isDetecting
            if detecting {
                // Greet once detection starts; the stretch clock counts from here
                picker.trigger(.greeting, at: now)
                stretchAt = now
            } else {
                picker.reset()
            }
        }

        let feedback = monitor.feedback
        if let exit = feedback.lastExit, exit.id != seenExit {
            seenExit = exit.id
            if exit.reason == .recovered, feedback.phase == .good, now - exit.detectedAt < BubbleLayout.recoverFresh {
                picker.trigger(.encourage, at: now)
            }
        }

        let study = timer.state
        // Only the moment focus turns into a break
        if study.phase == .rest, timerPhase == .focus { picker.trigger(.timerBreak, at: now) }
        timerPhase = study.phase

        if detecting, stretchReminder, now - stretchAt >= BubbleTiming.stretchInterval * FastTimers.scale {
            stretchAt = now
            picker.trigger(.stretch, at: now)
        }

        let kind = picker.update(at: now, conditions: BubbleConditions(
            posture: petMood(from: feedback.phase) == .bad,
            distance: monitor.distance.suggested,
            timer: study.running
        ))
        show(kind.map(HeadContent.bubble) ?? (study.running ? .timer(study) : nil))
    }

    private func show(_ next: HeadContent?) {
        guard next != content else { return }
        content = next
        guard let next, let container, let view else {
            host?.removeFromSuperview()
            host = nil
            view?.headFollower = nil
            pointer?.tapArea = nil
            pointer?.moved()
            return
        }
        let host = self.host ?? HeadHost(rootView: HeadView(content: next))
        host.rootView = HeadView(content: next)
        host.setFrameSize(host.fittingSize)
        if host.superview == nil { container.addSubview(host) }
        self.host = host
        let tappable = next.isTappable
        view.headFollower = { [weak self] head in self?.place(at: head, tappable: tappable) }
        view.followHead()
        if !tappable { pointer?.tapArea = nil }
        // Re-check right away, so a bubble appearing or leaving under a still pointer takes or releases clicks
        pointer?.moved()
    }

    // head is in view points with y down; the container has y up
    private func place(at head: CGPoint, tappable: Bool) {
        guard let host, let container else { return }
        let size = host.frame.size
        let box = CGRect(x: head.x - size.width / 2, y: head.y - BubbleLayout.headGap - size.height, width: size.width, height: size.height)
        let frame = CGRect(x: box.minX, y: container.bounds.height - box.maxY, width: size.width, height: size.height)
        host.frame = container.backingAlignedRect(frame, options: .alignAllEdgesNearest)
        if tappable { pointer?.tapArea = box }
    }
}

// A small click-through panel with only the timer, while the turtle is hidden and the timer runs
final class TimerCorner {
    private let timer: StudyTimer
    private var panel: NSPanel?
    // Set by TurtleOverlay from the "show over full screen" toggle
    var overFullScreen = true {
        didSet {
            if let panel { TurtleOverlay.setOverFullScreen(overFullScreen, on: panel) }
        }
    }

    init(timer: StudyTimer) {
        self.timer = timer
    }

    func setShown(_ shown: Bool) {
        if shown, panel == nil {
            let panel = TurtleOverlay.makePanel(.zero, overFullScreen: overFullScreen)
            panel.contentView = NSHostingView(rootView: CornerTimer(timer: timer))
            self.panel = panel
            fitScreen()
            panel.orderFrontRegardless()
        } else if !shown, let panel {
            panel.close()
            self.panel = nil
        }
    }

    func fitScreen() {
        guard let panel, let screen = NSScreen.screens.first else { return }
        let area = screen.visibleFrame, size = BubbleLayout.cornerSize, inset = BubbleLayout.cornerInset
        panel.setFrame(CGRect(x: area.maxX - inset - size.width, y: area.minY + inset, width: size.width, height: size.height), display: true)
    }
}
