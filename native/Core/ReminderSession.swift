import Foundation

public final class ReminderSession {
    public enum Stage: String { case entering, resting, ready, leaving }
    public let kind: ReminderKind
    public let entryDuration: Double
    public private(set) var stage: Stage = .entering
    public private(set) var started: Double
    public private(set) var contentStarted: Double?
    public private(set) var readyStarted: Double?

    public init(kind: ReminderKind, reducedMotion: Bool = false, now: Double) {
        self.kind = kind
        entryDuration = reducedMotion ? 0 : 2.65
        started = now
    }
    public func update(now: Double) {
        if stage == .entering, now - started >= entryDuration {
            contentStarted = now
            stage = kind == .eyes ? .resting : .ready
        }
        if stage == .resting, let contentStarted, now - contentStarted >= 20 {
            stage = .ready
            readyStarted = now
        }
    }
    public func remaining(now: Double) -> Int {
        guard let contentStarted else { return 20 }
        return max(0, Int(ceil(20 - (now - contentStarted))))
    }
    public func progress(now: Double) -> Double {
        guard let contentStarted else { return 0 }
        return min(1, max(0, (now - contentStarted) / 20))
    }
    public func shouldAutoFinish(now: Double) -> Bool {
        guard stage == .ready, let contentStarted else { return false }
        if kind == .eyes { return readyStarted.map { now - $0 >= 2.2 } ?? false }
        return now - contentStarted >= 6.5
    }
    @discardableResult
    public func beginLeaving() -> Bool {
        guard stage != .leaving else { return false }
        stage = .leaving
        return true
    }
}
