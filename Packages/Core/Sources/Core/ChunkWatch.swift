/// A consumer's private "chunks changed since I last looked" list. Each
/// subsystem that keeps something derived per chunk (autosave, thumbnails,
/// island counter) holds its own watch, so one consuming its changes never
/// hides them from another.
public final class ChunkWatch {
    private var chunks = Set<ChunkCoord>()

    public var count: Int { chunks.count }

    func add(_ chunk: ChunkCoord) {
        chunks.insert(chunk)
    }

    /// Hands over everything flagged since the last call and starts afresh.
    public func take() -> Set<ChunkCoord> {
        defer { chunks = [] }
        return chunks
    }

    /// Gives chunks back, e.g. because the work they were taken for failed.
    public func restore(_ given: some Sequence<ChunkCoord>) {
        chunks.formUnion(given)
    }
}
