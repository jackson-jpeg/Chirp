import Foundation
import Testing
@testable import ChirpCore

@Suite struct BirdTests {
    @Test func birdsAreIndicesIntoTheShippedSet() {
        #expect(Bird(palette: Bird.paletteCount - 1, chirp: Bird.chirpCount - 1) != nil)
        #expect(Bird(palette: Bird.paletteCount, chirp: 0) == nil)
        #expect(Bird(palette: 0, chirp: Bird.chirpCount) == nil)
        for n in 0...255 { _ = Bird.suggested(for: peer(UInt8(n))) }   // never traps
    }

    @Test func theBirdTravelsSignedInPresenceAndReachesTheRoster() throws {
        let id = newIdentity()
        let bird = try #require(Bird(palette: 5, chirp: 2))
        let payload = try Presence(identity: id, name: "Wren", bird: bird, at: t0).signedPayload(by: id)
        let p = try #require(Presence.verify(payload, origin: id.peerID, now: t0))
        #expect(p.bird == bird)
        var r = Roster()
        r.update(with: p, hops: 0, now: t0)
        #expect(r.person(id.peerID)?.bird == bird)
        // An index outside the set is refused even with a valid-looking body.
        var bad = payload
        let birdOffset = payload.count - 64 - 2
        bad[birdOffset] = 200
        #expect(Presence.verify(bad, origin: id.peerID, now: t0) == nil)
        // Changing the bird breaks the signature.
        var swapped = payload
        swapped[birdOffset + 1] = (swapped[birdOffset + 1] + 1) % Bird.chirpCount
        #expect(Presence.verify(swapped, origin: id.peerID, now: t0) == nil)
    }
}

@Suite struct PhotoTests {
    func photo(_ n: Int) -> Data { Data((0..<n).map { UInt8($0 % 251) }) }

    @Test func splitsWithinLimitsAndRoundTripsEachChunk() throws {
        #expect(PhotoChunk.split(Data()) == nil)
        #expect(PhotoChunk.split(photo(PhotoChunk.maxBytes + 1)) == nil)
        let chunks = try #require(PhotoChunk.split(photo(20_000)))
        #expect(chunks.count == 3 && chunks.allSatisfy { $0.count == 3 })
        for c in chunks { #expect(PhotoChunk.decode(c.encode()) == c) }
        #expect(chunks.allSatisfy { Packet.headerSize + $0.encode().count + 28 <= Packet.headerSize + Packet.maxPayload })
        var bad = chunks[0].encode(); bad[16] = 5          // index past count
        #expect(PhotoChunk.decode(bad) == nil)
    }

    @Test func assemblesInAnyOrderOnce() throws {
        let original = photo(30_000)
        let chunks = try #require(PhotoChunk.split(original))
        var a = PhotoAssembler()
        var result: Data?
        for c in chunks.reversed() { result = a.add(c, from: peer(1), now: t0) ?? result }
        #expect(result == original)
        // A relayed duplicate after completion does not produce it again.
        #expect(a.add(chunks[0], from: peer(1), now: t0) == nil)
        #expect(a.inFlight == 0)
    }

    @Test func partialPhotosAreBoundedInNumberAndTime() throws {
        var a = PhotoAssembler(maxInFlight: 2)
        for n in 1...3 {
            let first = try #require(PhotoChunk.split(photo(20_000))?.first)
            _ = a.add(first, from: peer(UInt8(n)), now: at(Double(n)))
        }
        #expect(a.inFlight == 2)
        let late = try #require(PhotoChunk.split(photo(20_000))?.first)
        _ = a.add(late, from: peer(9), now: at(PhotoAssembler.timeout + 10))
        #expect(a.inFlight == 1)
    }

    @Test func photosGoLastAndReachOneRelay() {
        #expect(PacketKind.allCases.allSatisfy { $0 == .photo || $0.sendPriority < PacketKind.photo.sendPriority })
        #expect(PacketKind.photo.initialTTL == 2)
    }
}
