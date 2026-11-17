import Foundation
import Testing
@testable import ChirpCore

@Suite struct LinkTests {
    @Test func serviceNamesRoundTripAndRejectStrangers() {
        let p = peer(7)
        #expect(Link.peer(fromServiceName: Link.serviceName(for: p)) == p)
        #expect(Link.peer(fromServiceName: "Jackson's iPhone") == nil)
        #expect(Link.peer(fromServiceName: "chirp-zz") == nil)
        #expect(Link.serviceName(for: p).utf8.count <= 63)
    }

    /// One link per pair: exactly one side dials.
    @Test func exactlyOneSideDials() {
        let a = peer(1), b = peer(2)
        #expect(Link.shouldDial(local: a, remote: b) != Link.shouldDial(local: b, remote: a))
        #expect(!Link.shouldDial(local: a, remote: a))
    }

    @Test func helloRoundTripsAndRejectsJunk() {
        #expect(Link.decodeHello(Link.hello(peer(3))) == peer(3))
        #expect(Link.decodeHello(Data("CHIRPLNK".utf8)) == nil)
        #expect(Link.decodeHello(Link.hello(peer(3)) + Data([0])) == nil)
        #expect(Link.decodeHello(packet(seq: 1).encode()) == nil)
    }

    @Test func framesSurviveAnySplit() {
        let bodies = [Data([1]), Data(repeating: 9, count: 300), packet(seq: 4).encode()]
        let stream = bodies.map(Link.frame).reduce(Data(), +)
        for size in [1, 3, 4, 5, 64, stream.count] {
            var d = Deframer()
            var out: [Data] = []
            var i = 0
            while i < stream.count {
                out += d.push(stream.subdata(in: i..<min(i + size, stream.count)))
                i += size
            }
            #expect(out == bodies)
            #expect(!d.broken)
        }
    }

    /// An oversized or empty frame breaks the link rather than buffering it.
    @Test func oversizedAndEmptyFramesBreakTheLink() {
        var big = Data()
        big.appendBigEndian(UInt32(Link.maxFrame + 1))
        var d = Deframer()
        #expect(d.push(Link.frame(Data([5])) + big).count == 1)
        #expect(d.broken)
        #expect(d.push(Link.frame(Data([6]))).isEmpty)

        var e = Deframer()
        _ = e.push(Data([0, 0, 0, 0]))
        #expect(e.broken)
    }

    @Test func aNewerLinkReplacesAndAStaleCloseIsIgnored() {
        var t = LinkTable<Int>()
        #expect(t.add(peer(1), 10) == nil)
        #expect(t.add(peer(1), 11) == 10)
        #expect(t.remove(10) == nil)
        #expect(t.peers == [peer(1)])
        #expect(t.remove(11) == peer(1))
        #expect(t.peers.isEmpty)
        #expect(t.add(peer(2), 12) == nil)
        #expect(t.add(peer(2), 12) == nil)
    }
}
