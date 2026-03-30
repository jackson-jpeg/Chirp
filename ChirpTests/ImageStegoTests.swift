import XCTest
import CryptoKit
@testable import Chirp

final class ImageStegoTests: XCTestCase {

    private let testKey = SymmetricKey(size: .bits256)
    private let wrongKey = SymmetricKey(size: .bits256)

    /// Create a test image of given size with solid color.
    private func makeImage(width: Int = 100, height: Int = 100) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    func testBasicRoundtrip() {
        let image = makeImage()
        let hidden = Data("secret image data".utf8)

        guard let pngData = ImageStego.encode(image: image, hidden: hidden, key: testKey) else {
            XCTFail("Encode returned nil")
            return
        }
        XCTAssertTrue(ImageStego.isPNG(pngData))

        guard let decoded = ImageStego.decode(pngData: pngData, key: testKey) else {
            XCTFail("Decode returned nil")
            return
        }
        XCTAssertEqual(decoded, hidden)
    }

    func testWrongKeyReturnsNil() {
        let image = makeImage()
        let hidden = Data("classified".utf8)
        guard let pngData = ImageStego.encode(image: image, hidden: hidden, key: testKey) else {
            XCTFail("Encode failed")
            return
        }
        XCTAssertNil(ImageStego.decode(pngData: pngData, key: wrongKey))
    }

    func testCapacity() {
        let cap = ImageStego.capacity(width: 100, height: 100)
        // 100x100 = 10000 pixels x 3 bits = 30000 bits - 32 header = 29968 bits = 3746 bytes - 31 overhead
        XCTAssertGreaterThan(cap, 3000)
    }

    func testLargePayload() {
        let image = makeImage(width: 200, height: 200)
        let cap = ImageStego.capacity(width: 200, height: 200)
        let hidden = Data(repeating: 0x42, count: min(cap, 1000))

        guard let pngData = ImageStego.encode(image: image, hidden: hidden, key: testKey) else {
            XCTFail("Encode failed for \(hidden.count) bytes")
            return
        }
        let decoded = ImageStego.decode(pngData: pngData, key: testKey)
        XCTAssertEqual(decoded, hidden)
    }

    func testExceedsCapacityReturnsNil() {
        let image = makeImage(width: 10, height: 10) // Tiny image
        let hidden = Data(repeating: 0xAA, count: 10000) // Way too much
        XCTAssertNil(ImageStego.encode(image: image, hidden: hidden, key: testKey))
    }

    func testIsPNG() {
        XCTAssertTrue(ImageStego.isPNG(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00])))
        XCTAssertFalse(ImageStego.isPNG(Data([0xFF, 0xD8, 0xFF]))) // JPEG
        XCTAssertFalse(ImageStego.isPNG(Data()))
    }

    func testEmptyHiddenReturnsNil() {
        let image = makeImage()
        XCTAssertNil(ImageStego.encode(image: image, hidden: Data(), key: testKey))
    }
}
