import SwiftUI

/// A button that acts on press, and keeps acting while held: after a short delay
/// (so a normal tap doesn't trigger it) it repeats quickly, like a spinner arrow.
/// `action` returns false to stop the repeat (e.g. the board is full).
struct RepeatButton<Label: View>: View {
    static var holdDelay: Duration { .milliseconds(800) }
    static var interval: Duration { .milliseconds(100) }

    let accessibilityLabel: String
    let action: () -> Bool
    @ViewBuilder let label: () -> Label
    @State private var repeating: Task<Void, Never>?

    var body: some View {
        label()
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in start() }
                    .onEnded { _ in stop() }
            )
            .accessibilityElement()
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { _ = action() }
    }

    private func start() {
        guard repeating == nil else { return }  // one press, one timer chain
        repeating = Task { @MainActor in
            guard action() else { return }
            try? await Task.sleep(for: Self.holdDelay)
            while !Task.isCancelled {
                if !action() { break }
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    private func stop() {
        repeating?.cancel()
        repeating = nil
    }
}
