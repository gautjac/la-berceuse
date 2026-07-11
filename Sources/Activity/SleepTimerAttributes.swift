import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// The sleep timer's Live Activity payload — shared by the app (which starts /
/// ends the activity) and the widget extension (which renders it). The lock
/// screen counts down on its own via `Text(timerInterval:)`, so the app never
/// needs to push per-second updates.
public struct SleepTimerAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// When the fade reaches silence.
        public var endDate: Date
        public init(endDate: Date) { self.endDate = endDate }
    }
    public init() {}
}
#endif
