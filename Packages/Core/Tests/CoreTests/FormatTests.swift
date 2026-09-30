import Foundation
import Testing
@testable import Core

@Suite struct FormatTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func relativeTimeBuckets() {
        #expect(relativeTime(from: now.addingTimeInterval(-20), now: now) == "just now")
        #expect(relativeTime(from: now.addingTimeInterval(-5 * 60), now: now) == "5m ago")
        #expect(relativeTime(from: now.addingTimeInterval(-3 * 3600), now: now) == "3h ago")
        #expect(relativeTime(from: now.addingTimeInterval(-2 * 86400), now: now) == "2d ago")
        #expect(!relativeTime(from: now.addingTimeInterval(-30 * 86400), now: now).contains("ago"))
    }

    @Test func durations() {
        #expect(formatDuration(ms: 10_000) == "<1m")
        #expect(formatDuration(ms: 12 * 60_000) == "12m")
        #expect(formatDuration(ms: 125 * 60_000) == "2h 5m")
    }
}
