import Foundation

/// The one decision on whether bytes may reach the radio (App Review 2.1(a):
/// a reviewer must be able to use the app alone, through Demo Mode, without
/// any of it reaching a real device nearby).
///
/// Carried over from 1.0's design (audit section 6: isolated below every
/// service at a single send gate). The transport calls `allows` for every
/// outbound packet and for every inbound one; nothing else sends.
public enum SendGate {
    /// Demo channels have IDs starting with the ASCII bytes "DEMO", so demo
    /// traffic is recognisable from the header alone, sandbox or not.
    static let demoPrefix: [UInt8] = Array("DEMO".utf8)

    public static func demoChannel(_ n: UInt8) -> ChannelID {
        var bytes = demoPrefix + [UInt8](repeating: 0, count: 12)
        bytes[15] = n
        return ChannelID(bytes: Data(bytes))!
    }

    public static func isDemo(_ channel: ChannelID) -> Bool {
        Array(channel.bytes.prefix(4)) == demoPrefix
    }

    /// Outbound: nothing while sandboxed, and never a demo-channel packet.
    public static func allowsSend(_ packet: Packet, sandboxed: Bool) -> Bool {
        !sandboxed && !isDemo(packet.channel)
    }

    /// Inbound from the radio: nothing while sandboxed (demo peers arrive
    /// through the simulator, not the air), and never a demo-channel packet.
    public static func allowsReceive(_ packet: Packet, sandboxed: Bool) -> Bool {
        !sandboxed && !isDemo(packet.channel)
    }
}
