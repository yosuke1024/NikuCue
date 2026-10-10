import Foundation

/// Injectable time source. Tests never use the real clock (docs/06 §5).
public protocol Clock: Sendable {
    var now: Date { get }
    var timeZone: TimeZone { get }
}

public struct SystemClock: Clock {
    public init() {}
    public var now: Date { Date() }
    public var timeZone: TimeZone { TimeZone.current }
}

/// A clock whose time and zone can be moved by tests ("travel", midnight crossing, DST).
public final class ManualClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date
    private var _timeZone: TimeZone

    public init(now: Date, timeZone: TimeZone) {
        _now = now
        _timeZone = timeZone
    }

    public var now: Date {
        get { lock.withLock { _now } }
        set { lock.withLock { _now = newValue } }
    }

    public var timeZone: TimeZone {
        get { lock.withLock { _timeZone } }
        set { lock.withLock { _timeZone = newValue } }
    }

    public func advance(by interval: TimeInterval) {
        lock.withLock { _now = _now.addingTimeInterval(interval) }
    }
}
