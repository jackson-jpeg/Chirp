import CoreGraphics
import Foundation
import MetalKit
import OSLog
import Security

/// Metal-based secure image renderer for view-once photos.
///
/// Renders directly to an ``MTKView`` using a fullscreen textured quad, bypassing
/// `UIImageView` to reduce the window of time decrypted pixel data lives in memory.
/// Call ``secureWipe()`` to overwrite the decrypted buffer with random bytes and
/// release all GPU resources.
@MainActor
final class DarkroomRenderer: NSObject, MTKViewDelegate {

    private let logger = Logger(subsystem: Constants.subsystem, category: "DarkroomRenderer")

    // MARK: - Metal state

    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
    private var texture: MTLTexture?
    private var vertexBuffer: MTLBuffer?

    // MARK: - Secure buffer tracking

    /// Pointer to the raw pixel buffer used to create the texture.
    /// Kept alive so we can overwrite it during ``secureWipe()``.
    nonisolated(unsafe) private var pixelBufferPointer: UnsafeMutableRawPointer?
    nonisolated(unsafe) private var pixelBufferSize: Int = 0

    // MARK: - Shader source

    /// Minimal Metal shader compiled at runtime so no separate `.metal` file is needed.
    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexIn {
        float2 position [[attribute(0)]];
        float2 texCoord [[attribute(1)]];
    };

    struct VertexOut {
        float4 position [[position]];
        float2 texCoord;
    };

    vertex VertexOut vertex_main(VertexIn in [[stage_in]]) {
        VertexOut out;
        out.position = float4(in.position, 0.0, 1.0);
        out.texCoord = in.texCoord;
        return out;
    }

    fragment float4 fragment_main(VertexOut in [[stage_in]],
                                   texture2d<float> tex [[texture(0)]]) {
        constexpr sampler s(mag_filter::linear, min_filter::linear);
        return tex.sample(s, in.texCoord);
    }
    """

    // MARK: - Vertex data (fullscreen quad, two triangles)

    /// Interleaved position (x,y) + texCoord (u,v) for 6 vertices.
    private static let quadVertices: [Float] = [
        // position   texCoord
        -1,  1,       0, 0,   // top-left
        -1, -1,       0, 1,   // bottom-left
         1, -1,       1, 1,   // bottom-right

        -1,  1,       0, 0,   // top-left
         1, -1,       1, 1,   // bottom-right
         1,  1,       1, 0,   // top-right
    ]

    // MARK: - Init

    override init() {
        super.init()
        setupMetal()
    }

    // MARK: - Setup

    private func setupMetal() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            logger.error("Metal is not available on this device")
            return
        }
        self.device = device

        guard let queue = device.makeCommandQueue() else {
            logger.error("Failed to create Metal command queue")
            return
        }
        commandQueue = queue

        // Compile shader from source string.
        do {
            let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
            guard let vertexFunc = library.makeFunction(name: "vertex_main"),
                  let fragmentFunc = library.makeFunction(name: "fragment_main") else {
                logger.error("Failed to locate shader functions")
                return
            }

            let vertexDescriptor = MTLVertexDescriptor()
            // Attribute 0: position (float2)
            vertexDescriptor.attributes[0].format = .float2
            vertexDescriptor.attributes[0].offset = 0
            vertexDescriptor.attributes[0].bufferIndex = 0
            // Attribute 1: texCoord (float2)
            vertexDescriptor.attributes[1].format = .float2
            vertexDescriptor.attributes[1].offset = MemoryLayout<Float>.stride * 2
            vertexDescriptor.attributes[1].bufferIndex = 0
            // Layout
            vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.stride * 4

            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunc
            pipelineDescriptor.fragmentFunction = fragmentFunc
            pipelineDescriptor.vertexDescriptor = vertexDescriptor
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            logger.error("Failed to compile Metal shaders: \(error.localizedDescription)")
            return
        }

        // Vertex buffer.
        let dataSize = Self.quadVertices.count * MemoryLayout<Float>.stride
        vertexBuffer = device.makeBuffer(
            bytes: Self.quadVertices,
            length: dataSize,
            options: .storageModeShared
        )
    }

    // MARK: - Image Loading

    /// Decode JPEG data and upload pixels to a Metal texture.
    ///
    /// The raw pixel buffer is retained for secure wiping.
    func loadImage(jpegData: Data) -> Bool {
        guard let device else {
            logger.error("No Metal device — cannot load image")
            return false
        }

        guard let dataProvider = CGDataProvider(data: jpegData as CFData),
              let cgImage = CGImage(
                  jpegDataProviderSource: dataProvider,
                  decode: nil,
                  shouldInterpolate: true,
                  intent: .defaultIntent
              ) else {
            logger.error("Failed to decode JPEG data")
            return false
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let bufferSize = bytesPerRow * height

        // Allocate pixel buffer.
        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: bufferSize,
            alignment: MemoryLayout<UInt8>.alignment
        )
        pixelBufferPointer = buffer
        pixelBufferSize = bufferSize

        // Render CGImage to BGRA pixel buffer.
        guard let context = CGContext(
            data: buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            logger.error("Failed to create CGContext for pixel extraction")
            buffer.deallocate()
            pixelBufferPointer = nil
            pixelBufferSize = 0
            return false
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Create Metal texture.
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        textureDescriptor.usage = .shaderRead

        guard let newTexture = device.makeTexture(descriptor: textureDescriptor) else {
            logger.error("Failed to create Metal texture")
            secureWipe()
            return false
        }

        newTexture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: buffer,
            bytesPerRow: bytesPerRow
        )

        texture = newTexture
        logger.info("Loaded darkroom image: \(width)x\(height)")
        return true
    }

    // MARK: - MTKViewDelegate

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // No-op — single image, no resize logic needed.
    }

    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated {
            drawOnMainActor(in: view)
        }
    }

    private func drawOnMainActor(in view: MTKView) {
        guard let pipelineState,
              let commandQueue,
              let vertexBuffer,
              let texture,
              let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor else {
            return
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Secure Wipe

    /// Overwrite the decrypted pixel buffer with cryptographically random bytes,
    /// release the Metal texture, and nil all references.
    ///
    /// After this call the renderer is inert and cannot display anything.
    func secureWipe() {
        // Overwrite pixel buffer with random data.
        if let buffer = pixelBufferPointer, pixelBufferSize > 0 {
            _ = SecRandomCopyBytes(kSecRandomDefault, pixelBufferSize, buffer)
            buffer.deallocate()
            logger.debug("Secure-wiped \(self.pixelBufferSize) bytes of pixel data")
        }
        pixelBufferPointer = nil
        pixelBufferSize = 0

        // Release GPU resources.
        texture = nil
        vertexBuffer = nil
        pipelineState = nil
        commandQueue = nil
        device = nil

        logger.info("DarkroomRenderer wiped and released")
    }

    deinit {
        // Safety net — if secureWipe() was not called, at least free the buffer.
        if let buffer = pixelBufferPointer, pixelBufferSize > 0 {
            _ = SecRandomCopyBytes(kSecRandomDefault, pixelBufferSize, buffer)
            buffer.deallocate()
        }
    }
}
