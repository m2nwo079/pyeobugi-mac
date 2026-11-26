import Foundation

private let distanceEnterRatio = 0.25
private let distanceExitRatio = 0.15
private let distanceHold: TimeInterval = 8
private let distanceMaxGap: TimeInterval = 1.6

public enum DistanceDirection: Sendable, Equatable {
    case closer, farther
}

public struct DistanceState: Sendable, Equatable {
    public var changedSince: TimeInterval?
    public var lastAt: TimeInterval?
    public var direction: DistanceDirection?
    public var suggested = false

    public init() {}

    public static let initial = DistanceState()
}

public func stepDistance(_ state: DistanceState, at: TimeInterval, size: Double?, baseline: Baseline?) -> DistanceState {
    guard let baseline, baseline.size.isFinite, baseline.size > 0,
          let size, size.isFinite, size > 0 else { return .initial }

    let delta = size / baseline.size - 1
    let magnitude = abs(delta)
    let direction: DistanceDirection = delta >= 0 ? .closer : .farther
    let interrupted = state.lastAt.map { at - $0 > distanceMaxGap || at < $0 } ?? true
    var reset = DistanceState.initial
    reset.lastAt = at

    if magnitude < distanceExitRatio || (state.direction != nil && state.direction != direction) { return reset }
    if state.suggested && !interrupted {
        var next = state
        next.lastAt = at
        return next
    }
    if magnitude < distanceEnterRatio { return reset }

    var next = DistanceState()
    let changedSince = interrupted ? at : state.changedSince ?? at
    next.changedSince = changedSince
    next.lastAt = at
    next.direction = direction
    next.suggested = at - changedSince >= distanceHold
    return next
}
