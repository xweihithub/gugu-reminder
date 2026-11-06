import Foundation
import CoreFoundation

public enum ReminderKind: String, CaseIterable {
    // 与旧版相同，到期时间一致时按眼睛、走动、喝水处理。
    case eyes, walk, water

    public var defaultMinutes: Int {
        switch self { case .eyes: return 40; case .walk: return 50; case .water: return 60 }
    }
    public var snoozeMinutes: Int { self == .eyes ? 5 : 10 }
    public var title: String {
        switch self { case .eyes: return "眼睛歇一会儿"; case .walk: return "起来走走呀"; case .water: return "喝口水吧" }
    }
    public var doneTitle: String {
        switch self { case .eyes: return "休息好了"; case .walk: return "这就起来"; case .water: return "喝好了" }
    }
    public var label: String {
        switch self { case .eyes: return "眼睛休息"; case .walk: return "走动"; case .water: return "喝水" }
    }
}

public enum ReminderError: Error, LocalizedError {
    case invalidInterval
    public var errorDescription: String? { "提醒间隔需为 1–1440 分钟的整数" }
}

// 时间单位保持毫秒，直接兼容 Electron 的 state.json。
public final class ReminderClock {
    public private(set) var intervals: [ReminderKind: Int] = [:]
    public private(set) var next: [ReminderKind: Double] = [:]
    public private(set) var pausedUntil: Double
    public static var now: Double { Date().timeIntervalSince1970 * 1000 }

    private static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }
        return n.doubleValue
    }
    private static func interval(_ value: Any?) -> Int? {
        guard let n = number(value), n >= 1, n <= 1440, n.rounded() == n else { return nil }
        return Int(n)
    }

    public init(saved: [String: Any] = [:], now: Double = ReminderClock.now) {
        pausedUntil = Self.number(saved["pausedUntil"]) ?? 0
        let oldIntervals = saved["intervals"] as? [String: Any] ?? [:]
        let oldNext = saved["next"] as? [String: Any] ?? [:]
        for kind in ReminderKind.allCases {
            let minutes = Self.interval(oldIntervals[kind.rawValue]) ?? kind.defaultMinutes
            intervals[kind] = minutes
            if let future = Self.number(oldNext[kind.rawValue]), future > now {
                next[kind] = future
            } else {
                next[kind] = max(now, pausedUntil) + Double(minutes) * 60000
            }
        }
    }

    public func due(now: Double = ReminderClock.now) -> ReminderKind? {
        guard now >= pausedUntil else { return nil }
        let earliest = ReminderKind.allCases.min { next[$0]! < next[$1]! }!
        return next[earliest]! <= now ? earliest : nil
    }

    public func finish(_ kind: ReminderKind, snooze: Bool = false, now: Double = ReminderClock.now) {
        next[kind] = now + Double(snooze ? kind.snoozeMinutes : intervals[kind]!) * 60000
    }

    @discardableResult
    public func setIntervals(_ values: [String: Any], now: Double = ReminderClock.now) throws -> [ReminderKind] {
        var valid: [ReminderKind: Int] = [:]
        for (key, value) in values {
            guard let kind = ReminderKind(rawValue: key), let minutes = Self.interval(value) else { throw ReminderError.invalidInterval }
            valid[kind] = minutes
        }
        var changed: [ReminderKind] = []
        for kind in ReminderKind.allCases {
            if let minutes = valid[kind], intervals[kind] != minutes {
                intervals[kind] = minutes
                next[kind] = max(now, pausedUntil) + Double(minutes) * 60000
                changed.append(kind)
            }
        }
        return changed
    }

    public func pause(now: Double = ReminderClock.now) {
        let end = now + 3600000
        reset(now: end)
        pausedUntil = end
    }
    public func reset(now: Double = ReminderClock.now) {
        pausedUntil = 0
        for kind in ReminderKind.allCases { next[kind] = now + Double(intervals[kind]!) * 60000 }
    }
    public var snapshot: [String: Any] {
        ["pausedUntil": pausedUntil,
         "intervals": Dictionary(uniqueKeysWithValues: intervals.map { ($0.key.rawValue, $0.value) }),
         "next": Dictionary(uniqueKeysWithValues: next.map { ($0.key.rawValue, $0.value) })]
    }
}

public final class StateStore {
    public let url: URL
    public private(set) var root: [String: Any]
    public let clock: ReminderClock

    public init(url: URL, now: Double = ReminderClock.now) {
        self.url = url
        root = (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        clock = ReminderClock(saved: root["reminders"] as? [String: Any] ?? [:], now: now)
    }

    public func save() throws {
        var updated = root
        updated["reminders"] = clock.snapshot
        let data = try JSONSerialization.data(withJSONObject: updated, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Foundation 的 atomic 写入使用同目录临时文件再替换，保留无关的历史字段。
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        root = updated
    }
}
