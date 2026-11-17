import Foundation
import Testing
@testable import ChirpCore

@Suite struct IdentityTests {
    @Test func peerIDIsTheHashOfTheSigningKeyAndRoundTripsThroughHex() {
        let id = newIdentity()
        #expect(id.peerID == PeerID(signingPublicKey: id.signingPublicKey))
        #expect(PeerID(hex: id.peerID.hex) == id.peerID)
        #expect(id.peerID.hex.count == 32)
        #expect(PeerID(hex: "zz") == nil)
    }

    @Test func loadOrCreateKeepsTheSameIdentityAcrossLoads() throws {
        let store = MemoryKeyStore()
        let a = try LocalIdentity.loadOrCreate(from: store)
        let b = try LocalIdentity.loadOrCreate(from: store)
        #expect(a.peerID == b.peerID)
        #expect(a.agreementPublicKey == b.agreementPublicKey)
        #expect(try LocalIdentity.loadOrCreate(from: MemoryKeyStore()).peerID != a.peerID)
    }

    @Test func signaturesVerifyOnlyForTheirKeyAndData() throws {
        let a = newIdentity(), b = newIdentity()
        let sig = try a.sign(Data("hi".utf8))
        #expect(LocalIdentity.verify(signature: sig, of: Data("hi".utf8), signingPublicKey: a.signingPublicKey))
        #expect(!LocalIdentity.verify(signature: sig, of: Data("ho".utf8), signingPublicKey: a.signingPublicKey))
        #expect(!LocalIdentity.verify(signature: sig, of: Data("hi".utf8), signingPublicKey: b.signingPublicKey))
    }

    @Test func pairwiseKeysAgreeFromBothSides() {
        let a = newIdentity(), b = newIdentity(), c = newIdentity()
        let ab = a.sharedKey(with: b.agreementPublicKey, purpose: "x")
        let ba = b.sharedKey(with: a.agreementPublicKey, purpose: "x")
        #expect(ab != nil && ab == ba)
        #expect(ab != c.sharedKey(with: b.agreementPublicKey, purpose: "x"))
        #expect(ab != a.sharedKey(with: b.agreementPublicKey, purpose: "y"))
    }
}

@Suite struct PacketTests {
    @Test func roundTripsEveryField() {
        let p = Packet(kind: .text, ttl: 3, hops: 1, origin: peer(7), epoch: 0xDEADBEEF, sequence: 42,
                       channel: .random(), payload: Data("hello".utf8))
        let wire = p.encode()
        #expect(wire.count == Packet.headerSize + 5)
        #expect(Packet.decode(wire) == p)
    }

    @Test func decodesFromASliceNotStartingAtZero() {
        let p = packet(seq: 9)
        let padded = Data([0xFF, 0xFF]) + p.encode()
        #expect(Packet.decode(padded.dropFirst(2)) == p)
    }

    @Test func rejectsMalformedInput() {
        let good = packet(seq: 1).encode()
        #expect(Packet.decode(Data()) == nil)
        #expect(Packet.decode(good.prefix(Packet.headerSize - 1)) == nil)
        var v = good; v[0] = 1                       // old version
        #expect(Packet.decode(v) == nil)
        var k = good; k[1] = 99                      // unknown kind
        #expect(Packet.decode(k) == nil)
        var t = good; t[2] = 0                       // dead TTL
        #expect(Packet.decode(t) == nil)
        var t2 = good; t2[2] = Packet.maxTTL + 1     // over the ceiling
        #expect(Packet.decode(t2) == nil)
        let huge = good + Data(count: Packet.maxPayload + 1)
        #expect(Packet.decode(huge) == nil)
    }

    @Test func randomBytesNeverTrap() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<5_000 {
            let n = Int.random(in: 0...120, using: &rng)
            var d = Data((0..<n).map { _ in UInt8.random(in: 0...255, using: &rng) })
            if n > 2, Bool.random(using: &rng) { d[0] = Packet.version; d[2] = 2 }
            _ = Packet.decode(d)
        }
    }

    @Test func relayCountsARealHopAndStopsAtTheLastOne() {
        let p = packet(.text, seq: 1)                 // TTL 4
        let r1 = p.relayed()!
        #expect(r1.ttl == 3 && r1.hops == 1 && r1.key == p.key)
        let r3 = r1.relayed()!.relayed()!
        #expect(r3.ttl == 1 && r3.hops == 3)
        #expect(r3.relayed() == nil)
    }

    @Test func floorReachesExactlyAsFarAsAudio() {
        #expect(PacketKind.floor.initialTTL == PacketKind.audio.initialTTL)
        #expect(!PacketKind.audio.reliable)
        #expect(PacketKind.text.reliable)
    }
}
