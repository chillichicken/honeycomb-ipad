import Core
import Metal
import MetalKit

/// One tile as the GPU sees it. Must match `TileInstance` in Shaders.metal.
struct TileInstance {
    var x: Float  // world units relative to the camera center, so precision never degrades far from the origin
    var y: Float
    var color: UInt32  // 0xRRGGBB
    var flags: UInt32  // bits 0-7 orientation, bit 8 outlined
}

/// Must match `Uniforms` in Shaders.metal.
struct GPUUniforms {
    var view: SIMD4<Float>
    var grid: SIMD4<Float>
    var misc: SIMD4<Float>
    var bgCenter: SIMD4<Float>
    var bgEdge: SIMD4<Float>
    var gridColor: SIMD4<Float>
    var accent: SIMD4<Float>
    var corners: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)
}

struct FrameStats {
    var drawnTiles = 0
    var cpuMs = 0.0
    var gpuMs = 0.0
}

/// Draws the board on the GPU. Every visible tile is one instance of a quad; the
/// fragment shader paints the shape, fabric grain, stitching, wall and selection
/// outline procedurally, so cost tracks the number of visible tiles at a few bytes
/// each and nothing else. The CPU work per frame is walking the viewport's buckets
/// and writing 16 bytes per tile.
@MainActor
final class TileRenderer {
    private static let framesInFlight = 3
    /// Beyond this many visible tiles they're a few pixels each and stacking order is skipped.
    private static let sortLimit = 65_536

    private let queue: MTLCommandQueue
    private let backdropPipeline: MTLRenderPipelineState
    private let tilePipeline: MTLRenderPipelineState
    private var buffers: [MTLBuffer?] = Array(repeating: nil, count: framesInFlight)
    private var frame = 0
    private let inFlight = DispatchSemaphore(value: framesInFlight)
    private let gpuTime = Locked(0.0)

    init?(device: MTLDevice, view: MTKView) {
        guard let queue = device.makeCommandQueue(), let library = device.makeDefaultLibrary() else { return nil }
        self.queue = queue

        func pipeline(_ vertex: String, _ fragment: String, blend: Bool) -> MTLRenderPipelineState? {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: vertex)
            d.fragmentFunction = library.makeFunction(name: fragment)
            d.colorAttachments[0].pixelFormat = view.colorPixelFormat
            if blend {
                let a = d.colorAttachments[0]!
                a.isBlendingEnabled = true
                a.sourceRGBBlendFactor = .sourceAlpha
                a.destinationRGBBlendFactor = .oneMinusSourceAlpha
                a.sourceAlphaBlendFactor = .one
                a.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            }
            return try? device.makeRenderPipelineState(descriptor: d)
        }
        guard let bg = pipeline("backdropVertex", "backdropFragment", blend: false),
            let tiles = pipeline("tileVertex", "tileFragment", blend: true)
        else { return nil }
        backdropPipeline = bg
        tilePipeline = tiles
        self.device = device
    }

    private let device: MTLDevice

    /// Renders one frame. Returns nil if the GPU is still busy with earlier frames
    /// (the caller just tries again next tick).
    func draw(_ editor: Editor, in view: MTKView) -> FrameStats? {
        guard inFlight.wait(timeout: .now()) == .success else { return nil }
        guard let drawable = view.currentDrawable, let pass = view.currentRenderPassDescriptor,
            let commands = queue.makeCommandBuffer()
        else {
            inFlight.signal()
            return nil
        }
        let start = CACurrentMediaTime()
        let board = editor.board
        let camera = editor.camera

        // shapes the marquee is touching right now get previewed as toggled
        var touched = Set<Tile>()
        if let m = editor.marquee {
            board.lattice.forEachTile(
                touchingMinX: min(m.from.x, m.to.x), minY: min(m.from.y, m.to.y),
                maxX: max(m.from.x, m.to.x), maxY: max(m.from.y, m.to.y)
            ) { touched.insert($0) }
        }

        let (buffer, count) = writeInstances(editor, touched: touched)
        var uniforms = makeUniforms(camera: camera, shape: board.shape, scale: view.contentScaleFactor)

        let encoder = commands.makeRenderCommandEncoder(descriptor: pass)!
        encoder.setRenderPipelineState(backdropPipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<GPUUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        if count > 0, let buffer {
            encoder.setRenderPipelineState(tilePipeline)
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<GPUUniforms>.stride, index: 1)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<GPUUniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: count)
        }
        encoder.endEncoding()
        commands.present(drawable)
        let gpuTime = gpuTime
        let inFlight = inFlight
        commands.addCompletedHandler { buffer in
            gpuTime.set((buffer.gpuEndTime - buffer.gpuStartTime) * 1000)
            inFlight.signal()
        }
        commands.commit()
        return FrameStats(drawnTiles: count, cpuMs: (CACurrentMediaTime() - start) * 1000, gpuMs: gpuTime.get())
    }

    // MARK: Instances

    /// Fills the next frame's instance buffer with everything on screen: the viewport's
    /// buckets (minus tiles that are mid-animation, drawn separately at their drawn
    /// position), the animating tiles, and the tiles being carried.
    private func writeInstances(_ editor: Editor, touched: Set<Tile>) -> (MTLBuffer?, Int) {
        let board = editor.board
        let camera = editor.camera
        let r = camera.visibleRect(margin: tileSize * 1.5)
        let easing = board.easing
        let carried = editor.drag?.items.map(\.tile) ?? []

        var upperBound = easing.count + carried.count
        board.store.forEachBucket(inMinX: r.minX, minY: r.minY, maxX: r.maxX, maxY: r.maxY) { _, tiles in
            upperBound += tiles.count
            return false
        }
        guard upperBound > 0 else { return (nil, 0) }

        let slot = frame % Self.framesInFlight
        frame += 1
        if buffers[slot] == nil || buffers[slot]!.length < upperBound * MemoryLayout<TileInstance>.stride {
            let capacity = max(upperBound + upperBound / 2, 4096)
            buffers[slot] = device.makeBuffer(length: capacity * MemoryLayout<TileInstance>.stride, options: .storageModeShared)
        }
        let buffer = buffers[slot]!
        let out = buffer.contents().bindMemory(to: TileInstance.self, capacity: upperBound)

        let cx = camera.center.x, cy = camera.center.y
        let selected = board.selected
        let marking = !selected.isEmpty || !touched.isEmpty
        @inline(__always) func instance(_ t: Tile) -> TileInstance {
            let outlined = marking && (selected.contains(t) != touched.contains(t))
            return TileInstance(
                x: Float(t.x - cx), y: Float(t.y - cy), color: t.color,
                flags: UInt32(t.orientation) | (outlined ? 0x100 : 0))
        }

        var n = 0
        if upperBound <= Self.sortLimit {
            // stacking order matters for overlapping tiles: draw bottom to top
            var tiles: [Tile] = []
            tiles.reserveCapacity(upperBound)
            board.store.forEachBucket(inMinX: r.minX, minY: r.minY, maxX: r.maxX, maxY: r.maxY) { _, bucket in
                if easing.isEmpty { tiles.append(contentsOf: bucket) } else { for t in bucket where !easing.contains(t) { tiles.append(t) } }
                return false
            }
            tiles.append(contentsOf: easing)
            tiles.append(contentsOf: carried)
            tiles.sort { $0.z < $1.z }
            for t in tiles {
                out[n] = instance(t)
                n += 1
            }
        } else {
            board.store.forEachBucket(inMinX: r.minX, minY: r.minY, maxX: r.maxX, maxY: r.maxY) { _, bucket in
                for t in bucket where easing.isEmpty || !easing.contains(t) {
                    out[n] = instance(t)
                    n += 1
                }
                return false
            }
            for t in easing { out[n] = instance(t); n += 1 }
            for t in carried { out[n] = instance(t); n += 1 }
        }
        return (buffer, n)
    }

    // MARK: Uniforms

    private func makeUniforms(camera: Camera, shape: TileShape, scale: CGFloat) -> GPUUniforms {
        let zoom = camera.zoom
        var spacing = shape.neighborDist
        while spacing * zoom < 28 { spacing *= 2 }  // thin the dot grid out when zoomed far away
        func mod(_ v: Double, _ m: Double) -> Double { v - (v / m).rounded(.down) * m }

        // unit corner vectors, two per SIMD4, for up to two orientations
        var packed = [SIMD4<Float>](repeating: .zero, count: 6)
        for (o, corners) in shape.cornerUnitVectors.enumerated() {
            for (k, c) in corners.enumerated() {
                let slot = o * 3 + k / 2
                if k % 2 == 0 { packed[slot].x = Float(c.x); packed[slot].y = Float(c.y) } else { packed[slot].z = Float(c.x); packed[slot].w = Float(c.y) }
            }
        }
        if shape.cornerUnitVectors.count == 1 {  // one orientation: the second is the same
            packed[3] = packed[0]; packed[4] = packed[1]; packed[5] = packed[2]
        }
        return GPUUniforms(
            view: SIMD4(Float(camera.size.width), Float(camera.size.height), Float(zoom), Float(tileSize)),
            grid: SIMD4(Float(spacing), Float(mod(camera.center.x, spacing)), Float(mod(camera.center.y, spacing)), Float(shape.neighborDist)),
            misc: SIMD4(Float(shape.cornerUnitVectors[0].count), Float(scale), Float(mod(camera.center.x, 14)), Float(mod(camera.center.y, 14))),
            bgCenter: Theme.bgCenter.simd, bgEdge: Theme.bgEdge.simd, gridColor: Theme.gridDot.simd, accent: Theme.accent.simd,
            corners: (packed[0], packed[1], packed[2], packed[3], packed[4], packed[5]))
    }
}

/// A value shared with the GPU completion handler, which runs on another thread.
final class Locked<T>: @unchecked Sendable {
    private var value: T
    private let lock = NSLock()
    init(_ value: T) { self.value = value }
    func set(_ v: T) { lock.lock(); value = v; lock.unlock() }
    func get() -> T { lock.lock(); defer { lock.unlock() }; return value }
}
