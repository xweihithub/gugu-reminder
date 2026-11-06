import XCTest
@testable import ReminderCore

final class ReminderCoreTests: XCTestCase {
    func testDefaultIntervalsCompletionAndSnooze() {
        let c = ReminderClock(now: 0)
        XCTAssertNil(c.due(now: 39 * 60000))
        XCTAssertEqual(c.due(now: 40 * 60000), .eyes)
        c.finish(.eyes, snooze: true, now: 40 * 60000)
        XCTAssertNil(c.due(now: 44 * 60000))
        XCTAssertEqual(c.due(now: 45 * 60000), .eyes)
        c.finish(.eyes, now: 45 * 60000)
        XCTAssertEqual(c.due(now: 50 * 60000), .walk)
        c.finish(.walk, now: 50 * 60000)
        XCTAssertEqual(c.due(now: 60 * 60000), .water)
        c.finish(.water, snooze: true, now: 60 * 60000)
        XCTAssertEqual(c.next[.water], 70 * 60000)
    }
    func testPauseResumeAndWake() {
        let c = ReminderClock(now: 0)
        c.pause(now: 0)
        XCTAssertNil(c.due(now: 3599999))
        XCTAssertNil(c.due(now: 3600000))
        XCTAssertEqual(c.next[.eyes], 100 * 60000)
        c.reset(now: 9000000)
        XCTAssertEqual(c.pausedUntil, 0)
        XCTAssertNil(c.due(now: 9000000))
        XCTAssertEqual(c.next[.eyes], 9000000 + 40 * 60000)
    }
    func testLegacyMissingWalkAndOverdueReminders() {
        let now = 100.0 * 60000
        let c = ReminderClock(saved: ["next": ["water": now + 60000, "eyes": now + 120000]], now: now)
        XCTAssertEqual(c.next[.walk], now + 50 * 60000)
        let all = ReminderClock(now: 0)
        XCTAssertEqual(all.due(now: 70 * 60000), .eyes)
        all.finish(.eyes, now: 70 * 60000)
        XCTAssertEqual(all.due(now: 70 * 60000), .walk)
        all.finish(.walk, now: 70 * 60000)
        XCTAssertEqual(all.due(now: 70 * 60000), .water)
        let restored = ReminderClock(saved: ["next": ["water": 1, "walk": 2, "eyes": 3]], now: now)
        XCTAssertNil(restored.due(now: now))
    }
    func testChangedIntervalsOnlyAndRestart() throws {
        let c = ReminderClock(now: 0)
        let walk = c.next[.walk]
        XCTAssertEqual(Set(try c.setIntervals(["water": 30, "eyes": 20], now: 1000)), Set([.water, .eyes]))
        XCTAssertEqual(c.next[.walk], walk)
        XCTAssertEqual(c.next[.water], 1000 + 30 * 60000)
        c.finish(.water, now: 2000)
        XCTAssertEqual(c.next[.water], 2000 + 30 * 60000)
        let restored = ReminderClock(saved: c.snapshot, now: 3000)
        XCTAssertEqual(restored.next, c.next)
        XCTAssertEqual(restored.intervals, c.intervals)
        let before = restored.next
        XCTAssertEqual(try restored.setIntervals(["water": 30], now: 4000), [])
        XCTAssertEqual(restored.next, before)
    }
    func testChangesDuringPauseStartAfterPause() throws {
        let c = ReminderClock(now: 0)
        c.pause(now: 0)
        try c.setIntervals(["eyes": 1], now: 60000)
        XCTAssertEqual(c.next[.eyes], 3660000)
        XCTAssertNil(c.due(now: 3600000))
        XCTAssertEqual(c.due(now: 3660000), .eyes)
    }
    func testInvalidIntervalsAreAtomic() throws {
        let c = ReminderClock(now: 0)
        let before = c.next
        for bad: Any in [0, -1, 1.5, 1441, Double.nan, Double.infinity, "30", NSNull(), true] {
            XCTAssertThrowsError(try c.setIntervals(["water": 30, "eyes": bad]))
            XCTAssertEqual(c.next, before)
            XCTAssertEqual(c.intervals[.water], 60)
        }
        XCTAssertThrowsError(try c.setIntervals(["unknown": 10]))
        try c.setIntervals(["eyes": 1, "water": 1440], now: 0)
        XCTAssertEqual(c.intervals[.eyes], 1)
        XCTAssertEqual(c.intervals[.water], 1440)
    }
    func testDamagedSavedValuesFallBackIndependently() {
        let c = ReminderClock(saved: ["intervals": ["eyes": 0, "walk": 25, "water": "bad"],
                                      "next": ["eyes": "bad"], "pausedUntil": "bad"], now: 0)
        XCTAssertEqual(c.intervals, [.eyes: 40, .walk: 25, .water: 60])
        XCTAssertEqual(c.next[.eyes], 40 * 60000)
    }
    func testStateStorePreservesLegacyAndReloads() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("state.json")
        let legacy: [String: Any] = ["resident": true, "preferences": ["安静"], "history": [["text": "历史"]],
                                   "reminders": ["intervals": ["water": 35], "next": ["water": 9999999]]]
        try JSONSerialization.data(withJSONObject: legacy).write(to: url)
        let store = StateStore(url: url, now: 0)
        XCTAssertEqual(store.clock.intervals[.water], 35)
        XCTAssertEqual(store.clock.next[.water], 9999999)
        try store.clock.setIntervals(["eyes": 20], now: 1000)
        try store.save()
        let reloaded = StateStore(url: url, now: 2000)
        XCTAssertEqual(reloaded.root["resident"] as? Bool, true)
        XCTAssertEqual(reloaded.root["preferences"] as? [String], ["安静"])
        XCTAssertEqual(reloaded.clock.intervals[.eyes], 20)
        XCTAssertEqual(reloaded.clock.next, store.clock.next)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
    func testEntryCountdownAndAutoFinish() {
        let s = ReminderSession(kind: .eyes, now: 0)
        s.update(now: 2.6)
        XCTAssertEqual(s.stage, .entering)
        s.update(now: 2.65)
        XCTAssertEqual(s.stage, .resting)
        XCTAssertEqual(s.remaining(now: 12.65), 10)
        s.update(now: 22.65)
        XCTAssertEqual(s.stage, .ready)
        XCTAssertFalse(s.shouldAutoFinish(now: 24.8))
        XCTAssertTrue(s.shouldAutoFinish(now: 24.9))
        XCTAssertTrue(s.beginLeaving())
        XCTAssertFalse(s.beginLeaving())
    }
    func testReducedMotionAndUnattendedReminders() {
        for kind in [ReminderKind.walk, .water] {
            let s = ReminderSession(kind: kind, reducedMotion: true, now: 0)
            s.update(now: 0)
            XCTAssertEqual(s.stage, .ready)
            XCTAssertFalse(s.shouldAutoFinish(now: 6.4))
            XCTAssertTrue(s.shouldAutoFinish(now: 6.5))
        }
        let eyes = ReminderSession(kind: .eyes, reducedMotion: true, now: 0)
        eyes.update(now: 0)
        XCTAssertEqual(eyes.stage, .resting)
        XCTAssertEqual(eyes.remaining(now: 0), 20)
    }
}
