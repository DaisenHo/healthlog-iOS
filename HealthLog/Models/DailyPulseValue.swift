import Foundation

/// One day of pulse as the server resolves it (`GET /api/measurements/series-batch`,
/// rollup tier): `value` is the day's mean of its local hours' means (server
/// v1.40.1, #1107), `count`, `minValue` and `maxValue` stay over every reading.
public struct DailyPulseValue: Sendable, Equatable {
    public let day: Date
    public let mean: Double
    public let count: Int
    public let min: Double?
    public let max: Double?

    public init(day: Date, mean: Double, count: Int, min: Double? = nil, max: Double? = nil) {
        self.day = day
        self.mean = mean
        self.count = count
        self.min = min
        self.max = max
    }
}
