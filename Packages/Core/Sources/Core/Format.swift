import Foundation

/// "just now", "5m ago", "3h ago", "2d ago", then a short date.
public func relativeTime(from date: Date, now: Date = .now) -> String {
    let minutes = Int(now.timeIntervalSince(date) / 60)
    if minutes < 1 { return "just now" }
    if minutes < 60 { return "\(minutes)m ago" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)h ago" }
    let days = hours / 24
    if days < 7 { return "\(days)d ago" }
    return date.formatted(.dateTime.month(.abbreviated).day())
}

/// "<1m", "12m", "2h 5m".
public func formatDuration(ms: Int) -> String {
    let totalMinutes = Int((Double(ms) / 60000).rounded())
    if totalMinutes < 1 { return "<1m" }
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
}
