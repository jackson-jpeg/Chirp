import Foundation
import Testing
@testable import ChirpCore

@Suite struct InviteTests {
    @Test func aLinkRoundTripsTheBirdhouseAndItsKey() throws {
        let birdhouse = Channel.newLocked(name: "Ski trip")
        let link = try #require(BirdhouseInvite.link(for: birdhouse))
        #expect(link.absoluteString.hasPrefix("https://chirpchirps.com/join/#k="))
        let back = try #require(BirdhouseInvite.parse(url: link))
        #expect(back == birdhouse)
        #expect(BirdhouseInvite.parse(link.absoluteString) == birdhouse)
    }

    @Test func theKeyIsOnlyInTheFragment() throws {
        let birdhouse = Channel.newLocked(name: "Camp")
        let link = try #require(BirdhouseInvite.link(for: birdhouse))
        // What a browser sends to the server: scheme, host, path, query. Never the fragment.
        #expect(link.query() == nil)
        #expect(!link.path().contains(birdhouse.inviteCode))
        #expect(link.fragment()?.contains(birdhouse.inviteCode) == true)
    }

    @Test func namesWithSpacesAndSymbolsSurvive() throws {
        let birdhouse = Channel.newLocked(name: "Mom & Dad's cruise 🚢")
        let link = try #require(BirdhouseInvite.link(for: birdhouse))
        #expect(BirdhouseInvite.parse(url: link)?.name == "Mom & Dad's cruise 🚢")
    }

    @Test func theAppSchemeOpensTheSameBirdhouse() throws {
        let birdhouse = Channel.newLocked(name: "Festival")
        let link = try #require(BirdhouseInvite.link(for: birdhouse))
        let app = try #require(URL(string: "chirpchirps://join#\(link.fragment(percentEncoded: true)!)"))
        #expect(BirdhouseInvite.parse(url: app) == birdhouse)
    }

    @Test func aPastedMessageAroundTheLinkWorks() throws {
        let birdhouse = Channel.newLocked(name: "Ski trip")
        let link = try #require(BirdhouseInvite.link(for: birdhouse))
        #expect(BirdhouseInvite.parse("Join my birdhouse on ChirpChirps: \(link.absoluteString) see you up there") == birdhouse)
        #expect(BirdhouseInvite.parse("(\(link.absoluteString))") == birdhouse)
    }

    @Test func aBareCodeJoinsWithAPlainName() {
        let birdhouse = Channel.newLocked(name: "Ski trip")
        let back = BirdhouseInvite.parse("  \(birdhouse.inviteCode)\n")
        #expect(back?.id == birdhouse.id && back?.seed == birdhouse.seed)
        #expect(back?.name == BirdhouseInvite.fallbackName)
    }

    @Test func openAndDemoChannelsHaveNoInvite() {
        #expect(BirdhouseInvite.link(for: .nearby) == nil)
        #expect(BirdhouseInvite.link(for: Channel.newOpen(name: "x")) == nil)
        #expect(BirdhouseInvite.link(for: DemoBirdhouse.channel) == nil)
        // Built by hand, a demo-channel link is still refused.
        #expect(BirdhouseInvite.parse("https://chirpchirps.com/join/#k=\(DemoBirdhouse.channel.inviteCode)&n=x") == nil)
        #expect(BirdhouseInvite.parse(DemoBirdhouse.channel.inviteCode) == nil)
        // An open channel's 22-character code is not a birdhouse invite.
        #expect(BirdhouseInvite.parse(Channel.newOpen(name: "x").inviteCode) == nil)
    }

    @Test func otherLinksAndJunkAreRefused() {
        let code = Channel.newLocked(name: "x").inviteCode
        #expect(BirdhouseInvite.parse("https://example.com/join/#k=\(code)&n=x") == nil)
        #expect(BirdhouseInvite.parse("https://chirpchirps.com/privacy/#k=\(code)&n=x") == nil)
        #expect(BirdhouseInvite.parse("https://chirpchirps.com/join/#n=nokey") == nil)
        #expect(BirdhouseInvite.parse("https://chirpchirps.com/join/#k=short&n=x") == nil)
        #expect(BirdhouseInvite.parse("hello there") == nil)
        #expect(BirdhouseInvite.parse("") == nil)
    }

    @Test func namesAreCleanedAndCapped() throws {
        #expect(BirdhouseInvite.cleanName("  Ski\u{0007} trip \n") == "Ski trip")
        #expect(BirdhouseInvite.cleanName(String(repeating: "a", count: 50)).count == BirdhouseInvite.maxNameLength)
        let code = Channel.newLocked(name: "x").inviteCode
        let blank = try #require(BirdhouseInvite.parse("https://chirpchirps.com/join/#k=\(code)&n=%20%20"))
        #expect(blank.name == BirdhouseInvite.fallbackName)
    }

    @Test func wwwAndAMissingSlashAreTheSamePage() {
        let birdhouse = Channel.newLocked(name: "x")
        #expect(BirdhouseInvite.parse("https://www.chirpchirps.com/join#k=\(birdhouse.inviteCode)&n=x") == birdhouse)
    }
}
