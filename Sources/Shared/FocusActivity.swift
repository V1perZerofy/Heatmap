import Foundation
import ActivityKit

/// The focus timer shown on the lock screen and in the Dynamic Island.
public struct FocusAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// When running: the moment the timer would have started without pauses.
        public var start: Date
        /// When paused: time on the clock.
        public var pausedElapsed: TimeInterval?
        /// 0 = open session
        public var targetMinutes: Int

        public init(start: Date, pausedElapsed: TimeInterval?, targetMinutes: Int) {
            self.start = start
            self.pausedElapsed = pausedElapsed
            self.targetMinutes = targetMinutes
        }

        public var running: Bool { pausedElapsed == nil }
    }

    public var habitName: String
    public var symbol: String
    public var colorIndex: Int

    public init(habitName: String, symbol: String, colorIndex: Int) {
        self.habitName = habitName
        self.symbol = symbol
        self.colorIndex = colorIndex
    }
}
