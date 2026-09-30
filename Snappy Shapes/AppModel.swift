import SwiftUI
import Core

/// Which screen is showing, which puzzle is open, and keeping it saved.
@Observable @MainActor
final class AppModel {
    enum Screen { case start, playing }

    private(set) var screen = Screen.start
    private(set) var puzzles: [PuzzleMeta] = []
    private(set) var errorMessage: String?
    /// The shape the player asked for, waiting on their OK to clear the board.
    private(set) var pendingShape: ShapeID?
    let editor = Editor()

    private let store: PuzzleStoring
    private let persistence: BoardPersistence
    private var currentID: String?
    private var name = ""
    private var activeMs = 0
    private var lastSaveAt = Date()
    private var saving = false
    @ObservationIgnored private var loop: Task<Void, Never>?

    init(store: PuzzleStoring = FilePuzzleStore(root: .applicationSupportDirectory.appending(path: "puzzles", directoryHint: .isDirectory))) {
        self.store = store
        persistence = BoardPersistence(puzzles: store)
        Task { await refresh() }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await self?.tick()
            }
        }
    }

    deinit { loop?.cancel() }

    // MARK: Screens

    func newPuzzle(shape id: ShapeID) {
        editor.reset(shape: .of(id))
        currentID = nil
        name = "\(TileShape.of(id).label) · \(Date.now.formatted(.dateTime.day().month(.abbreviated)))"
        activeMs = 0
        screen = .playing
    }

    /// Switching shape starts a new puzzle (the old one stays saved), so a board
    /// with tiles on it asks first.
    func requestShapeSwitch(to id: ShapeID) {
        guard id != editor.board.shape.id else { return }
        if editor.board.store.size == 0 {
            newPuzzle(shape: id)  // nothing to lose
        } else {
            pendingShape = id
        }
    }

    func confirmShapeSwitch() async {
        guard let id = pendingShape else { return }
        pendingShape = nil
        await saveNow()
        newPuzzle(shape: id)
    }

    func cancelShapeSwitch() { pendingShape = nil }

    func open(_ meta: PuzzleMeta) async {
        do {
            let centroid = try await persistence.load(id: meta.id, into: editor.board)
            editor.didLoad(centroid: centroid)
            currentID = meta.id
            name = meta.name
            activeMs = meta.activeMs
            screen = .playing
        } catch {
            errorMessage = "Couldn't open \"\(meta.name)\"."
        }
    }

    func delete(_ meta: PuzzleMeta) async {
        try? await store.remove(id: meta.id)
        await refresh()
    }

    /// Saves, then back to the start screen.
    func goHome() async {
        await saveNow()
        screen = .start
        await refresh()
    }

    func refresh() async {
        puzzles = (try? await store.list()) ?? []
    }

    // MARK: Saving

    /// Saves if anything changed. Safe to call any time; overlapping calls are skipped.
    func saveNow() async {
        guard screen == .playing, !saving, editor.board.store.hasUnsavedChanges else { return }
        saving = true
        defer { saving = false }
        do {
            currentID = try await persistence.save(editor.board, id: currentID, name: name, activeMs: activeMs)
            lastSaveAt = Date()
        } catch {
            errorMessage = "Couldn't save."  // the changes stay flagged; the next tick retries
        }
    }

    /// Once a second: count active time, and autosave ~2s after the last edit
    /// (or every 30s regardless), never while a finger is mid-drag.
    private func tick() async {
        guard screen == .playing else { return }
        let sinceEdit = Date().timeIntervalSince(editor.lastEditAt)
        if sinceEdit < 30 { activeMs += 1000 }
        guard editor.drag == nil else { return }
        if sinceEdit > 2 || Date().timeIntervalSince(lastSaveAt) > 30 { await saveNow() }
    }
}
