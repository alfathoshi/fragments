//
//  MomentActivityAttributes.swift
//  fragments
//
//  Created on 9/16/26.
//

import ActivityKit
import Foundation

/// Defines the data contract for the Moment Recording Live Activity.
///
/// - `MomentActivityAttributes` holds **static** data set at session start.
/// - `ContentState` holds **dynamic** data that updates as the session progresses.
struct MomentActivityAttributes: ActivityAttributes {

    // MARK: - Dynamic State (updated during the live activity)
    public struct ContentState: Codable, Hashable {
        /// Number of fragments captured so far.
        var fragmentCount: Int
        /// Human-readable location name (e.g. "Jakarta, ID")
        var location: String
    }

    // MARK: - Static Data (set once at session start)
    /// Session start date — used by the Lock Screen timer via `Text(_:style: .timer)`.
    var startDate: Date
    /// Unique identifier for the session (so we can find the right activity to update).
    var sessionID: String
}
