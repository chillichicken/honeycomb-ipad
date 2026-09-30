import Foundation

/// Thrown when a chunk file can't be read back.
public struct CorruptChunkError: Error, Equatable {}

/// One chunk's tiles as flat arrays: positions keep full float precision and a
/// chunk of thousands of tiles is a few dozen KB. Only the settled position
/// (`tx`/`ty`) is stored, never the mid-ease one.
public struct ChunkData: Equatable, Sendable {
    public var x: [Double]
    public var y: [Double]
    public var orientation: [UInt8]
    public var color: [TileColor]

    public var count: Int { x.count }

    public init(tiles: [Tile]) {
        x = tiles.map(\.tx)
        y = tiles.map(\.ty)
        orientation = tiles.map { UInt8($0.orientation) }
        color = tiles.map(\.color)
    }

    /// Fresh tiles, at rest on their saved spots, in stored (bottom-to-top) order.
    public func makeTiles() -> [Tile] {
        (0..<count).map { i in
            Tile(x: x[i], y: y[i], color: color[i], orientation: Int(orientation[i]))
        }
    }

    // MARK: File format
    //
    // "HCK1" magic, tile count (UInt32), then the four arrays back to back.
    // Little-endian, which is every platform this app runs on.

    private static let magic: UInt32 = 0x314B_4348

    public func serialized() -> Data {
        var data = Data(capacity: 8 + count * 21)
        data.append(contentsOf: withUnsafeBytes(of: Self.magic.littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: UInt32(count).littleEndian, Array.init))
        x.withUnsafeBytes { data.append(contentsOf: $0) }
        y.withUnsafeBytes { data.append(contentsOf: $0) }
        orientation.withUnsafeBytes { data.append(contentsOf: $0) }
        color.withUnsafeBytes { data.append(contentsOf: $0) }
        return data
    }

    public init(serialized data: Data) throws {
        let bytes = [UInt8](data)
        guard bytes.count >= 8 else { throw CorruptChunkError() }
        let header = bytes.withUnsafeBytes { (UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self)),
                                              UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self))) }
        let n = Int(header.1)
        guard header.0 == Self.magic, bytes.count == 8 + n * 21 else { throw CorruptChunkError() }
        func read<T: Numeric>(_ type: T.Type, at offset: Int) -> [T] {
            var out = [T](repeating: 0, count: n)
            let size = n * MemoryLayout<T>.stride
            bytes.withUnsafeBytes { raw in
                out.withUnsafeMutableBytes {
                    $0.copyMemory(from: UnsafeRawBufferPointer(rebasing: raw[offset..<offset + size]))
                }
            }
            return out
        }
        x = read(Double.self, at: 8)
        y = read(Double.self, at: 8 + n * 8)
        orientation = read(UInt8.self, at: 8 + n * 16)
        color = read(TileColor.self, at: 8 + n * 17)
    }
}
