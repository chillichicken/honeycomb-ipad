import Foundation

/// Puzzles as folders: `<root>/<id>/meta.json` plus `<root>/<id>/chunks/<x>_<y>.chunk`.
///
/// Every file is written atomically, and `meta.json` is written last, so a
/// listing never points at a puzzle whose chunks haven't landed. A crash midway
/// through a many-chunk save can leave some chunks newer than others, which is
/// the price of not having a single transaction over many files.
public final class FilePuzzleStore: PuzzleStoring {
    private let root: URL

    public init(root: URL) {
        self.root = root
    }

    private var files: FileManager { .default }

    private func folder(_ id: String) -> URL { root.appendingPathComponent(id, isDirectory: true) }
    private func chunksFolder(_ id: String) -> URL { folder(id).appendingPathComponent("chunks", isDirectory: true) }
    private func metaURL(_ id: String) -> URL { folder(id).appendingPathComponent("meta.json") }
    private func chunkURL(_ id: String, _ c: ChunkCoord) -> URL {
        chunksFolder(id).appendingPathComponent("\(c.x)_\(c.y).chunk")
    }

    private static func coord(fromFileName name: String) -> ChunkCoord? {
        guard name.hasSuffix(".chunk") else { return nil }
        let parts = name.dropLast(".chunk".count).split(separator: "_")
        guard parts.count == 2, let x = Int(parts[0]), let y = Int(parts[1]) else { return nil }
        return ChunkCoord(x: x, y: y)
    }

    public func list() async throws -> [PuzzleMeta] {
        guard files.fileExists(atPath: root.path) else { return [] }
        let folders = try files.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        let metas = folders.compactMap { url -> PuzzleMeta? in
            guard let data = try? Data(contentsOf: url.appendingPathComponent("meta.json")) else { return nil }
            return try? JSONDecoder().decode(PuzzleMeta.self, from: data)
        }
        return metas.sorted { $0.updatedAt > $1.updatedAt }
    }

    public func save(_ request: SaveRequest) async throws -> String {
        let id = request.id ?? UUID().uuidString
        try files.createDirectory(at: chunksFolder(id), withIntermediateDirectories: true)

        for w in request.writes {
            try w.data.serialized().write(to: chunkURL(id, w.coord), options: .atomic)
        }
        for c in request.deletes { try? files.removeItem(at: chunkURL(id, c)) }
        if request.replaceAll {
            let keep = Set(request.writes.map(\.coord))
            let existing = try files.contentsOfDirectory(at: chunksFolder(id), includingPropertiesForKeys: nil)
            for url in existing {
                if let c = Self.coord(fromFileName: url.lastPathComponent), !keep.contains(c) {
                    try files.removeItem(at: url)
                }
            }
        }

        let now = Date()
        let createdAt = (try? Data(contentsOf: metaURL(id)))
            .flatMap { try? JSONDecoder().decode(PuzzleMeta.self, from: $0) }?.createdAt ?? now
        let meta = PuzzleMeta(
            id: id, name: request.name, shape: request.shape, createdAt: createdAt, updatedAt: now,
            activeMs: request.activeMs, tileCount: request.tileCount)
        try JSONEncoder().encode(meta).write(to: metaURL(id), options: .atomic)
        return id
    }

    public func load(id: String) async throws -> StoredPuzzle {
        guard let data = try? Data(contentsOf: metaURL(id)) else { throw PuzzleNotFoundError() }
        let meta = try JSONDecoder().decode(PuzzleMeta.self, from: data)
        var chunks: [ChunkRecord] = []
        let urls = (try? files.contentsOfDirectory(at: chunksFolder(id), includingPropertiesForKeys: nil)) ?? []
        for url in urls {
            guard let coord = Self.coord(fromFileName: url.lastPathComponent) else { continue }
            chunks.append(ChunkRecord(coord: coord, data: try ChunkData(serialized: Data(contentsOf: url))))
        }
        return StoredPuzzle(meta: meta, chunks: chunks)
    }

    public func remove(id: String) async throws {
        if files.fileExists(atPath: folder(id).path) { try files.removeItem(at: folder(id)) }
    }
}
