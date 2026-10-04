import Foundation
import ActivityKit

/// Live Activity für den aktuell laufenden Zeitblock
/// (Sperrbildschirm + Dynamic Island des iPhone 14 Pro).
struct DayActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var title: String
        var symbol: String
        var start: Date
        var end: Date
        var nextTitle: String?
        var nextStart: Date?
    }

    /// ID des PlanItems, zu dem die Aktivität gehört.
    var itemID: String
}
