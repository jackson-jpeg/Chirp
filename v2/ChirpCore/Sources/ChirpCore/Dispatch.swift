import Foundation

/// Dispatch: the one place a packet off the air becomes something the app
/// uses, and the one place the app's actions become packets.
///
/// In, for every packet a link hands over:
/// 1. The router decides (own echo, blocked, duplicate, replay) and gives the
///    relay copy, which goes out whether or not this phone can open it.
/// 2. Text-like packets are held for catch up, still sealed and signed.
/// 3. Admission: ping, battery and Find only from a friend, on the whisper
///    channel to me.
/// 4. The channel opens the payload (a locked or whisper channel this phone is
///    not on cannot), and the signature is checked against the key the roster
///    learned from that person's signed presence. No presence yet, no message.
/// 5. One switch on `PacketKind` turns it into an `Event`, plus the acks a
///    text needs.
///
/// Out: `make…` seals, signs and numbers packets the same way, so both sides
/// are one set of rules. Audio is sealed but not signed (50 a second); the
/// floor that admits it is signed.
///
/// A value with no callbacks and no clock: the app passes `now`, sends what
/// `Output` says, and shows the events. 1.0 dispatched on magic strings in
/// the payload (audit section 7) and acked texts on channels it was not on.
public struct Dispatch: Sendable {
    public enum Event: Equatable, Sendable {
        /// Someone's presence was new or changed (name, bird, keys).
        case presence(Roster.Person)
        case text(StoredText)
        /// One of my texts got a tick from `from`.
        case delivered(UUID, from: PeerID)
        case floor(FloorMessage, channel: ChannelID)
        case audio(Data, from: PeerID, epoch: UInt32, sequence: UInt32, channel: ChannelID)
        case rollCall(RollCall, from: PeerID, channel: ChannelID)
        case help(HelpCall, from: PeerID, channel: ChannelID)
        case meetup(Meetup, from: PeerID, channel: ChannelID)
        case ping(from: PeerID)
        case battery(BatteryLevel, from: PeerID)
        case photo(Data, id: UUID, from: PeerID, channel: ChannelID)
        case find(Find.Message, from: PeerID)
        /// Someone proved they are on a locked channel I am on: they are now a
        /// friend (once per person and channel).
        case friend(PeerID, channel: ChannelID)
    }

    /// What one received packet asks of the app.
    public struct Output: Equatable, Sendable {
        public var events: [Event] = []
        /// To every link but the one it came in on.
        public var relay: Packet?
        /// To every link (acks, which are relayed like texts).
        public var broadcast: [Packet] = []
        /// To the one phone it came from (catch-up answers).
        public var reply: [Packet] = []
    }

    /// A ping at most this often from each friend.
    public static let pingInterval: TimeInterval = 10
    /// How many delivered text-like packets are remembered, so the same one
    /// live and again in a catch-up bundle is shown once.
    public static let deliveredMemory = 2048
    /// How often `memberships` says "I am on this channel" on each locked one.
    public static let memberInterval: TimeInterval = 10

    public let identity: LocalIdentity
    public var me: PeerID { identity.peerID }
    public let epoch: UInt32
    public var name: String
    public var bird: Bird

    public private(set) var router: Router
    public private(set) var roster = Roster()
    public private(set) var ledger = TextLedger()
    public private(set) var held = CatchUpStore()
    public private(set) var blocked: Set<PeerID> = []
    /// Who has proved they are on each locked channel I joined: a signed
    /// packet from them that opened with that channel's key. Open channels
    /// prove nothing (their code is the channel ID, which every packet on them
    /// carries in the clear), and the nearby channel is everyone in range.
    public private(set) var members: [ChannelID: Set<PeerID>] = [:]

    /// People on a locked channel with me, never anyone blocked. Ping, battery
    /// and Find come only from them and go only to them. Never "everyone heard
    /// on Nearby": 1.0 sent battery to strangers (audit section 5).
    public var friends: Set<PeerID> {
        members.values.reduce(into: Set<PeerID>()) { $0.formUnion($1) }.subtracting(blocked)
    }

    /// Channels this phone is on, the nearby channel always among them.
    public private(set) var channels: [ChannelID: Channel] = [ChannelID.nearby: .nearby]
    private var sequences: [PacketKind: UInt32] = [:]
    private var photos = PhotoAssembler()
    private var pings = RateLimiter(interval: Dispatch.pingInterval)
    private var delivered: Set<Packet.Key> = []
    private var deliveredOrder: [Packet.Key] = []
    private var memberSent: [ChannelID: Date] = [:]

    public init(identity: LocalIdentity, name: String, bird: Bird = .default,
                epoch: UInt32 = UInt32.random(in: 1...UInt32.max), ledger: TextLedger = TextLedger()) {
        self.identity = identity
        self.name = name
        self.bird = bird
        self.epoch = epoch
        self.ledger = ledger
        self.router = Router(local: identity.peerID)
    }

    // MARK: Settings the app changes

    public mutating func join(_ channel: Channel) { channels[channel.id] = channel }
    public mutating func leave(_ id: ChannelID) {
        guard !id.isNearby else { return }
        channels.removeValue(forKey: id)
        members.removeValue(forKey: id)
        memberSent.removeValue(forKey: id)
    }
    public var joined: Set<ChannelID> { Set(channels.keys) }

    /// The block list, applied in the router (no delivery, no relay), to
    /// catch-up answers and to the thread.
    public mutating func setBlocked(_ peers: Set<PeerID>) {
        blocked = peers
        router.blocked = peers
    }

    /// Forget people not heard for `Roster.staleAfter`.
    public mutating func prune(now: Date) -> [PeerID] { roster.prune(now: now) }

    // MARK: In

    public mutating func receive(_ packet: Packet, from link: PeerID, now: Date) -> Output {
        var out = Output()
        let decision = router.accept(packet, now: now)
        guard decision.deliver else { return out }
        out.relay = decision.relay
        if CatchUpStore.heldKinds.contains(packet.kind), !Whisper.isFor(packet, me: me) {
            held.hold(packet, now: now)
        }
        handle(packet, link: link, now: now, into: &out)
        return out
    }

    private mutating func handle(_ packet: Packet, link: PeerID, now: Date, into out: inout Output) {
        guard Admission.accepts(packet, me: me, friends: friends, blocked: blocked) else { return }
        let header = packet.sealedHeader

        if packet.kind == .presence {
            guard packet.channel.isNearby, let p = Presence.verify(packet.payload, origin: packet.origin, now: now) else { return }
            let before = roster.person(p.peer)
            roster.update(with: p, hops: packet.hops, now: now)
            if let after = roster.person(p.peer),
               before == nil || before?.name != after.name || before?.bird != after.bird || before?.hops != after.hops {
                out.events.append(.presence(after))
            }
            return
        }
        roster.heard(packet.origin, now: now)

        guard let channel = channel(for: packet), let plain = channel.open(packet.payload, header: header) else { return }

        if packet.kind == .audio {
            out.events.append(.audio(plain, from: packet.origin, epoch: packet.epoch, sequence: packet.sequence,
                                     channel: packet.channel))
            return
        }
        if packet.kind == .catchUp {
            catchUp(plain, packet: packet, link: link, now: now, into: &out)
            return
        }

        guard let key = roster.person(packet.origin)?.signingKey else { return }
        if packet.kind == .text {
            guard let body = TextBody.verify(plain, header: header, signingKey: key) else { return }
            noteMember(packet, into: &out)
            let sender = roster.person(packet.origin)?.name ?? packet.origin.shortCode
            let on = Whisper.isFor(packet, me: me) ? joined.union([packet.channel]) : joined
            switch ledger.receive(body, channel: packet.channel, from: packet.origin, senderName: sender, joined: on) {
            case .stored:
                if let stored = ledger.texts.last { out.events.append(.text(stored)) }
                if let ack = try? make(.ack, on: packet.channel, body: Ack.payload(for: body.id), now: now) { out.broadcast.append(ack) }
            case .duplicate:
                if let ack = try? make(.ack, on: packet.channel, body: Ack.payload(for: body.id), now: now) { out.broadcast.append(ack) }
            case .notJoined:
                break
            }
            return
        }

        guard let body = Signed.open(plain, header: header, signingKey: key) else { return }
        noteMember(packet, into: &out)
        if CatchUpStore.heldKinds.contains(packet.kind), !remember(packet.key) { return }

        switch packet.kind {
        case .ack:
            if let id = Ack.messageID(in: body), ledger.ack(id, from: packet.origin, channel: packet.channel, me: me) {
                out.events.append(.delivered(id, from: packet.origin))
            }
        case .floor:
            if let m = FloorMessage.decode(body), m.sender == packet.origin {
                out.events.append(.floor(m, channel: packet.channel))
            }
        case .rollCall:
            if let r = RollCall.decode(body) { out.events.append(.rollCall(r, from: packet.origin, channel: packet.channel)) }
        case .help:
            if let h = HelpCall.decode(body) { out.events.append(.help(h, from: packet.origin, channel: packet.channel)) }
        case .meetup:
            if let m = Meetup.decode(body) { out.events.append(.meetup(m, from: packet.origin, channel: packet.channel)) }
        case .ping:
            if body.isEmpty, pings.allow(packet.origin, now: now) { out.events.append(.ping(from: packet.origin)) }
        case .battery:
            if let b = BatteryLevel.decode(body) { out.events.append(.battery(b, from: packet.origin)) }
        case .photo:
            if let chunk = PhotoChunk.decode(body), let photo = photos.add(chunk, from: packet.origin, now: now) {
                out.events.append(.photo(photo, id: chunk.photoID, from: packet.origin, channel: packet.channel))
            }
        case .find:
            if let m = Find.Message.decode(body) { out.events.append(.find(m, from: packet.origin)) }
        case .member, .audio, .text, .presence, .catchUp:
            break
        }
    }

    /// A signed packet that opened with a locked channel's key came from
    /// someone holding that key.
    private mutating func noteMember(_ packet: Packet, into out: inout Output) {
        guard channels[packet.channel]?.isLocked == true, packet.origin != me else { return }
        if members[packet.channel, default: []].insert(packet.origin).inserted {
            out.events.append(.friend(packet.origin, channel: packet.channel))
        }
    }

    /// The channel a packet is on, if this phone can open it: one it joined,
    /// or the whisper channel between its sender and me.
    private func channel(for packet: Packet) -> Channel? {
        if let c = channels[packet.channel] { return c }
        guard Whisper.isFor(packet, me: me), let them = roster.person(packet.origin) else { return nil }
        return Whisper.channel(me: identity, them: packet.origin, theirAgreementKey: them.agreementKey, name: them.name)
    }

    /// A request is answered with what this phone holds; a bundle's packets
    /// are handled like fresh ones, without the router's replay window (they
    /// are old by design) but with every other rule.
    private mutating func catchUp(_ body: Data, packet: Packet, link: PeerID, now: Date, into out: inout Output) {
        guard packet.origin == link else { return }   // one link only, never relayed
        if let request = CatchUpRequest.decode(body) {
            let answer = held.packets(for: request, requester: packet.origin, blocked: blocked, now: now)
            for bundle in CatchUpBundle.pack(answer, limit: Packet.maxPayload - 64) {
                if let p = try? make(.catchUp, on: .nearby, body: bundle, now: now) { out.reply.append(p) }
            }
        } else if let inner = CatchUpBundle.unpack(body) {
            for p in inner where p.origin != me && !blocked.contains(p.origin) {
                handle(p, link: link, now: now, into: &out)
            }
        }
    }

    /// False when this text-like packet was already delivered.
    private mutating func remember(_ key: Packet.Key) -> Bool {
        guard delivered.insert(key).inserted else { return false }
        deliveredOrder.append(key)
        if deliveredOrder.count > Self.deliveredMemory { delivered.remove(deliveredOrder.removeFirst()) }
        return true
    }

    // MARK: Out

    public enum MakeError: Error, Equatable { case notOnChannel, notFriend }

    /// A packet of `kind` on `channel`, numbered, signed (all but audio and
    /// presence, which signs itself) and sealed for the channel.
    public mutating func make(_ kind: PacketKind, on channelID: ChannelID, body: Data, now: Date) throws -> Packet {
        guard let channel = outgoingChannel(channelID) else { throw MakeError.notOnChannel }
        let seq = sequences[kind, default: 0]
        sequences[kind] = seq &+ 1
        let draft = Packet(kind: kind, origin: me, epoch: epoch, sequence: seq, channel: channelID, payload: Data())
        let header = draft.sealedHeader
        let plain = (kind == .audio || kind == .presence || kind == .catchUp) ? body
            : try Signed.payload(body, by: identity, header: header)
        let wire = try channel.seal(plain, header: header)
        return Packet(kind: kind, origin: me, epoch: epoch, sequence: seq, channel: channelID, payload: wire)
    }

    private func outgoingChannel(_ id: ChannelID) -> Channel? {
        if let c = channels[id] { return c }
        for person in roster.visible(excluding: blocked) where Whisper.channelID(me, person.id) == id {
            return Whisper.channel(me: identity, them: person.id, theirAgreementKey: person.agreementKey, name: person.name)
        }
        return nil
    }

    /// The whisper channel to one person (talk to one, ping, battery, Find).
    public func whisperChannel(to peer: PeerID) -> ChannelID { Whisper.channelID(me, peer) }

    public mutating func presence(now: Date) throws -> Packet {
        let body = try Presence(identity: identity, name: name, bird: bird, at: now).signedPayload(by: identity)
        return try make(.presence, on: .nearby, body: body, now: now)
    }

    /// A text, recorded with one tick. Its signature covers the body and the
    /// header, as `TextBody.verify` expects.
    public mutating func text(_ words: String, on channelID: ChannelID, now: Date) throws -> Packet {
        guard let channel = outgoingChannel(channelID) else { throw MakeError.notOnChannel }
        let seq = sequences[.text, default: 0]
        sequences[.text] = seq &+ 1
        let draft = Packet(kind: .text, origin: me, epoch: epoch, sequence: seq, channel: channelID, payload: Data())
        let body = TextBody(sentAt: now, text: words)
        let wire = try channel.seal(try body.signedPayload(by: identity, header: draft.sealedHeader), header: draft.sealedHeader)
        ledger.recordOutgoing(body, channel: channelID, me: me, myName: name)
        return Packet(kind: .text, origin: me, epoch: epoch, sequence: seq, channel: channelID, payload: wire)
    }

    public mutating func floor(_ message: FloorMessage, on channel: ChannelID, now: Date) throws -> Packet {
        try make(.floor, on: channel, body: message.encode(), now: now)
    }

    public mutating func audio(_ frame: Data, on channel: ChannelID, now: Date) throws -> Packet {
        try make(.audio, on: channel, body: frame, now: now)
    }

    /// Ping, battery and Find go only to a friend, on the whisper channel.
    public mutating func toFriend(_ kind: PacketKind, _ body: Data, peer: PeerID, now: Date) throws -> Packet {
        guard friends.contains(peer), !blocked.contains(peer) else { throw MakeError.notFriend }
        return try make(kind, on: whisperChannel(to: peer), body: body, now: now)
    }

    /// "I am on this channel", once per `memberInterval` on each locked
    /// channel I joined (at once for one just joined). The app sends these with
    /// its presence heartbeat.
    public mutating func memberships(now: Date) -> [Packet] {
        var out: [Packet] = []
        for channel in channels.values.sorted(by: { $0.id.description < $1.id.description }) where channel.isLocked {
            if let last = memberSent[channel.id], now.timeIntervalSince(last) < Self.memberInterval { continue }
            guard let p = try? make(.member, on: channel.id, body: Data(), now: now) else { continue }
            memberSent[channel.id] = now
            out.append(p)
        }
        return out
    }

    /// "I'm back": the channels I am on and when I last heard each.
    public mutating func catchUpRequest(since: [ChannelID: Date], now: Date) throws -> Packet {
        let request = CatchUpRequest(channels: joined.sorted { $0.description < $1.description }
            .map { ($0, since[$0] ?? now.addingTimeInterval(-CatchUpStore.maxAge)) })
        return try make(.catchUp, on: .nearby, body: request.encode(), now: now)
    }
}
