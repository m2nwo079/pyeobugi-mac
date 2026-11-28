import Foundation
import Testing
@testable import PostureCore

// All times are in seconds

private let quiet = BubbleConditions()
private let show = BubbleTiming.showDuration
private let gap = BubbleTiming.minGap

@Suite struct BubblePickerTests {
    @Test func postureStaysWhileConditionLasts() {
        var picker = BubblePicker()
        #expect(picker.update(at: 0, conditions: BubbleConditions(posture: true)) == .posture)
        #expect(picker.update(at: 60, conditions: BubbleConditions(posture: true)) == .posture)
        #expect(picker.update(at: 61, conditions: quiet) == nil)
    }

    @Test func oneOffShowsForShowDuration() {
        var picker = BubblePicker()
        picker.trigger(.encourage, at: 0)
        #expect(picker.update(at: 0, conditions: quiet) == .encourage)
        #expect(picker.update(at: show - 0.001, conditions: quiet) == .encourage)
        #expect(picker.update(at: show, conditions: quiet) == nil)
    }

    @Test func overlapShowsHighestPriority() {
        var picker = BubblePicker()
        picker.trigger(.encourage, at: 0)
        picker.trigger(.timerBreak, at: 0)
        #expect(picker.update(at: 0, conditions: BubbleConditions(posture: true)) == .posture)
    }

    @Test func urgentReplacesShown() {
        var picker = BubblePicker()
        picker.trigger(.greeting, at: 0)
        #expect(picker.update(at: 0, conditions: quiet) == .greeting)
        #expect(picker.update(at: 0.1, conditions: BubbleConditions(posture: true)) == .posture)
    }

    @Test func keepsGapBetweenBubbles() {
        var picker = BubblePicker()
        picker.trigger(.greeting, at: 0)
        _ = picker.update(at: 0, conditions: quiet)
        picker.trigger(.timerBreak, at: 0)
        // Not right after the greeting ends
        #expect(picker.update(at: show, conditions: quiet) == nil)
        #expect(picker.update(at: show + gap, conditions: quiet) == .timerBreak)
    }

    @Test func sameKindWaitsCooldown() throws {
        var picker = BubblePicker()
        picker.trigger(.encourage, at: 0)
        #expect(picker.update(at: 0, conditions: quiet) == .encourage)
        let after = show + gap
        picker.trigger(.encourage, at: after)
        #expect(picker.update(at: after, conditions: quiet) == nil)
        let later = try #require(BubbleTiming.cooldowns[.encourage]) + 1
        picker.trigger(.encourage, at: later)
        #expect(picker.update(at: later, conditions: quiet) == .encourage)
    }

    @Test func distanceIsTappable() {
        var picker = BubblePicker()
        let kind = picker.update(at: 0, conditions: BubbleConditions(distance: true))
        #expect(kind == .distance)
        #expect(kind?.isTappable == true)
        #expect(BubbleKind.allCases.filter(\.isTappable) == [.distance])
    }

    @Test func resetClearsQueuedAndShown() {
        var picker = BubblePicker()
        picker.trigger(.greeting, at: 0)
        _ = picker.update(at: 0, conditions: quiet)
        picker.reset()
        #expect(picker.update(at: 0.1, conditions: quiet) == nil)
    }

    @Test func injectedCooldownsApply() {
        var picker = BubblePicker(cooldowns: BubbleTiming.cooldowns.mapValues { $0 / 60 })
        picker.trigger(.stretch, at: 0)
        #expect(picker.update(at: 0, conditions: quiet) == .stretch)
        _ = picker.update(at: show, conditions: quiet)
        picker.trigger(.stretch, at: 21)
        #expect(picker.update(at: 21, conditions: quiet) == .stretch)
    }
}

@Suite struct BubblesDuringTimerTests {
    private let running = BubbleConditions(timer: true)

    @Test func postureStillShows() {
        var picker = BubblePicker()
        #expect(picker.update(at: 0, conditions: BubbleConditions(posture: true, timer: true)) == .posture)
    }

    @Test func breakStillShows() {
        var picker = BubblePicker()
        picker.trigger(.timerBreak, at: 0)
        #expect(picker.update(at: 0, conditions: running) == .timerBreak)
    }

    @Test func othersAreHeldBack() {
        var picker = BubblePicker()
        picker.trigger(.greeting, at: 0)
        picker.trigger(.stretch, at: 0)
        picker.trigger(.encourage, at: 0)
        #expect(picker.update(at: 0, conditions: BubbleConditions(distance: true, timer: true)) == nil)
    }

    @Test func heldBackShowsOnceTimerStops() {
        var picker = BubblePicker()
        picker.trigger(.greeting, at: 0)
        #expect(picker.update(at: 0, conditions: running) == nil)
        #expect(picker.update(at: 0.1, conditions: quiet) == .greeting)
    }
}
