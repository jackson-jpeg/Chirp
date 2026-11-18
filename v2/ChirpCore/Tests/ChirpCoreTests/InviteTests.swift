import Foundation
import Testing
@testable import ChirpCore

@Suite struct InviteTests {
    @Test func aLinkRoundTripsTheFlockAndItsKey() throws {
        let flock = Channel.newLocked(name: "Ski trip")
        let link = try #require(FlockInvite.link(for: flock))
        #expect(link.absoluteString.hasPrefix("https://chirpchirps.com/join/#k="))
        let back = try #require(FlockInvite.parse(url: link))
        #expect(back == flock)
        #expect(FlockInvite.parse(link.absoluteString) == flock)
    }

    @Test func theKeyIsOnlyInTheFragment() throws {
        let flock = Channel.newLocked(name: "Camp")
        let link = try #require(FlockInvite.link(for: flock))
        // What a browser sends to the server: scheme, host, path, query. Never the fragment.
        #expect(link.query() == nil)
        #expect(!link.path().contains(flock.inviteCode))
        #expect(link.fragment()?.contains(flock.inviteCode) == true)
    }

    @Test func namesWithSpacesAndSymbolsSurvive() throws {
        let flock = Channel.newLocked(name: "Mom & Dad's cruise 🚢")
        let link = try #require(FlockInvite.link(for: flock))
        #expect(FlockInvite.parse(url: link)?.name == "Mom & Dad's cruise 🚢")
    }

    @Test func theAppSchemeOpensTheSameFlock() throws {
        let flock = Channel.newLocked(name: "Festival")
        let link = try #require(FlockInvite.link(for: flock))
        let app = try #require(URL(string: "chirpchirps://join#\(link.fragment(percentEncoded: true)!)"))
        #expect(FlockInvite.parse(url: app) == flock)
    }

    @Test func aPastedMessageAroundTheLinkWorks() throws {
        let flock = Channel.newLocked(name: "Ski trip")
        let link = try #require(FlockInvite.link(for: flock))
        #expect(FlockInvite.parse("Join my flock on ChirpChirps: \(link.absoluteString) see you up there") == flock)
        #expect(FlockInvite.parse("(\(link.absoluteString))") == flock)
    }

    @Test func aBareCodeJoinsWithAPlainName() {
        let flock = Channel.newLocked(name: "Ski trip")
        let back = FlockInvite.parse("  \(flock.inviteCode)\n")
        #expect(back?.id == flock.id && back?.seed == flock.seed)
        #expect(back?.name == FlockInvite.fallbackName)
    }

    @Test func openAndDemoChannelsHaveNoInvite() {
        #expect(FlockInvite.link(for: .nearby) == nil)
        #expect(FlockInvite.link(for: Channel.newOpen(name: "x")) == nil)
        #expect(FlockInvite.link(for: DemoFlock.channel) == nil)
        // Built by hand, a demo-channel link is still refused.
        #expect(FlockInvite.parse("https://chirpchirps.com/join/#k=\(DemoFlock.channel.inviteCode)&n=x") == nil)
        #expect(FlockInvite.parse(DemoFlock.channel.inviteCode) == nil)
        // An open channel's 22-character code is not a flock invite.
        #expect(FlockInvite.parse(Channel.newOpen(name: "x").inviteCode) == nil)
    }

    @Test func otherLinksAndJunkAreRefused() {
        let code = Channel.newLocked(name: "x").inviteCode
        #expect(FlockInvite.parse("https://example.com/join/#k=\(code)&n=x") == nil)
        #expect(FlockInvite.parse("https://chirpchirps.com/privacy/#k=\(code)&n=x") == nil)
        #expect(FlockInvite.parse("https://chirpchirps.com/join/#n=nokey") == nil)
        #expect(FlockInvite.parse("https://chirpchirps.com/join/#k=short&n=x") == nil)
        #expect(FlockInvite.parse("hello there") == nil)
        #expect(FlockInvite.parse("") == nil)
    }

    @Test func namesAreCleanedAndCapped() throws {
        #expect(FlockInvite.cleanName("  Ski\u{0007} trip \n") == "Ski trip")
        #expect(FlockInvite.cleanName(String(repeating: "a", count: 50)).count == FlockInvite.maxNameLength)
        let code = Channel.newLocked(name: "x").inviteCode
        let blank = try #require(FlockInvite.parse("https://chirpchirps.com/join/#k=\(code)&n=%20%20"))
        #expect(blank.name == FlockInvite.fallbackName)
    }

    @Test func wwwAndAMissingSlashAreTheSamePage() {
        let flock = Channel.newLocked(name: "x")
        #expect(FlockInvite.parse("https://www.chirpchirps.com/join#k=\(flock.inviteCode)&n=x") == flock)
    }
}
