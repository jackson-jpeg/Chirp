import Foundation

/// How a flock is started and joined (Jackson, Inbox chirp-2-0-flock-join,
/// 2026-11-18): you name the flock, and friends join by an invite link you
/// send them from the share sheet. The link carries the flock's key, so
/// anyone who has it can hear the flock: it is meant for the people you
/// send it to, like a door key.
///
/// The link is `https://chirpchirps.com/join/#k=<invite code>&n=<name>`.
/// The key sits after `#`, which a browser never sends to a server, so
/// opening the link on a phone without the app shows chirpchirps.com's join
/// page and the key still stays on that phone. The app also takes
/// `chirpchirps://join#...` (the join page's "Open in ChirpChirps" button),
/// and a pasted link or a bare 43-character code, so a friend whose link
/// did not open the app can paste it on "Join a flock".
///
/// Only locked flocks have invites: an open channel has no key to share.
/// A demo channel ID is refused, so a link can never put a real flock on
/// an ID that `SendGate` keeps off the air.
public enum FlockInvite {
    public static let host = "chirpchirps.com"
    public static let scheme = "chirpchirps"
    public static let maxNameLength = 32
    /// What a flock is called when the link carries no usable name.
    public static let fallbackName = "Your flock"

    /// The link to share for `channel`, or nil for an open or demo channel.
    public static func link(for channel: Channel) -> URL? {
        guard channel.isLocked, !SendGate.isDemo(channel.id) else { return nil }
        var c = URLComponents()
        c.scheme = "https"
        c.host = host
        c.path = "/join/"
        c.fragment = fragment(code: channel.inviteCode, name: cleanName(channel.name))
        return c.url
    }

    /// The flock in a link, a pasted message that contains one, or a bare
    /// invite code. Nil when there is no locked flock in it.
    public static func parse(_ text: String) -> Channel? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let whole = channel(fromToken: trimmed) { return whole }
        // A message around the link ("Join my flock: https://..."): try each word.
        for token in trimmed.split(whereSeparator: { $0.isWhitespace }) {
            let t = token.trimmingCharacters(in: CharacterSet(charactersIn: "<>()[]\"'.,;!?"))
            if let found = channel(fromToken: t) { return found }
        }
        return nil
    }

    /// The flock in an opened URL (universal link or the app's own scheme).
    public static func parse(url: URL) -> Channel? {
        guard isInviteURL(url) else { return nil }
        return parseFragment(url.fragment(percentEncoded: true) ?? "")
    }

    /// The name a person typed, as a flock is called: trimmed, no control
    /// characters, at most `maxNameLength` characters.
    public static func cleanName(_ raw: String) -> String {
        let kept = raw.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let s = String(String.UnicodeScalarView(kept))
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(s.prefix(maxNameLength)).trimmingCharacters(in: .whitespaces)
    }

    // MARK: Parts

    public static func isInviteURL(_ url: URL) -> Bool {
        let path = url.path(percentEncoded: false)
        switch url.scheme?.lowercased() {
        case "https", "http":
            let h = url.host()?.lowercased()
            return (h == host || h == "www.\(host)") && (path == "/join" || path == "/join/")
        case scheme:
            return url.host()?.lowercased() == "join"
        default:
            return false
        }
    }

    private static func channel(fromToken token: String) -> Channel? {
        if let url = URL(string: token), url.scheme != nil {
            return parse(url: url)
        }
        // A bare code: only the locked kind (16-byte ID and 16-byte seed).
        guard token.count == 43 else { return nil }
        return locked(code: token, name: fallbackName)
    }

    private static func parseFragment(_ fragment: String) -> Channel? {
        var code: String?
        var name: String?
        for pair in fragment.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            let value = kv[1].replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? ""
            switch kv[0] {
            case "k": code = value
            case "n": name = value
            default: continue
            }
        }
        guard let code else { return nil }
        let clean = cleanName(name ?? "")
        return locked(code: code, name: clean.isEmpty ? fallbackName : clean)
    }

    private static func locked(code: String, name: String) -> Channel? {
        guard let c = Channel.join(inviteCode: code, name: name), c.isLocked, !SendGate.isDemo(c.id) else { return nil }
        return c
    }

    private static func fragment(code: String, name: String) -> String {
        // Unreserved characters only, so every app that linkifies the URL keeps it whole.
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let n = name.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        return "k=\(code)&n=\(n)"
    }
}
