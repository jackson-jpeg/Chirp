import Foundation
import Observation

/// On-device classifier for objectionable incoming message text (App Store
/// Guideline 1.2: apps with user-generated content need a way to filter it).
///
/// This only classifies. It never deletes or rewrites anything — the caller
/// (`TextMessageService` / the message view) decides what "objectionable"
/// means for display, typically collapsing the bubble behind a "Hidden
/// message, tap to show" affordance. Keeping classification and presentation
/// separate means a bad match never destroys data, and Jackson can loosen or
/// tighten the wordlist later without touching storage.
///
/// Only inbound text is meant to be run through this. Chirp does not censor
/// what a person sends, only what they are shown from strangers on the mesh.
///
/// ## Evasion handling
///
/// Mesh chat is exactly the kind of low-friction, no-account text field where
/// people try `f.u.c.k`, `f u c k`, and `n1gg3r` to slip past a naive filter,
/// and where `Scunthorpe`, `cockpit`, and `therapist` must never be flagged by
/// one. Both requirements fall out of the same trick: never call `contains`
/// against the raw string. Instead, split the (lowercased, diacritic-folded,
/// leetspeak-substituted) text into runs of letters and digits — punctuation
/// and whitespace both count as separators, so `f.u.c.k` and `f u c k`
/// tokenize identically. A legitimate word like "cockpit" is always a single
/// run, so it is only ever compared to the blocklist as a whole ("cockpit" ==
/// "cock"? no) and never as a substring ("cockpit" contains "cock"? never
/// asked). An evasion that has been chopped into fragments is caught by
/// re-joining short runs of *consecutive* tokens and testing whether that
/// concatenation exactly equals a blocklisted word.
@Observable
@MainActor
final class TextFilter {

    private(set) var isEnabled: Bool

    /// Called whenever the enabled state changes, with the new value.
    var onChange: ((Bool) -> Void)?

    private let storageKey = "com.chirpchirp.textFilterEnabled"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // No stored value means first launch: on by default, per the review
        // requirement that the filter protects people out of the box.
        if let stored = defaults.object(forKey: storageKey) as? Bool {
            isEnabled = stored
        } else {
            isEnabled = true
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        persist()
    }

    private func persist() {
        defaults.set(isEnabled, forKey: storageKey)
        onChange?(isEnabled)
    }

    /// Whether `text` should be treated as objectionable. Cheap enough to
    /// call on every inbound message: tokenizing and matching a short chat
    /// message against a few dozen words is microseconds of work.
    func isObjectionable(_ text: String) -> Bool {
        guard isEnabled else { return false }
        let tokens = Self.tokenize(text)
        guard !tokens.isEmpty else { return false }

        // Try every run of consecutive tokens starting at each position.
        // Window size 1 catches whole-word matches ("cunt") without ever
        // touching substrings of longer innocent words. Larger windows
        // reassemble words an evader chopped up with spaces or punctuation
        // ("f u c k", "f.u.c.k"). The length cap keeps this from doing
        // pointless work joining unrelated tokens in a long message.
        for start in tokens.indices {
            var combined = ""
            for end in start..<tokens.count {
                combined += tokens[end]
                if combined.count > Self.longestCandidateLength {
                    break
                }
                if Self.matchesBlockedWord(combined) {
                    return true
                }
            }
        }
        return false
    }

    /// Whether one candidate run is a blocklisted word, allowing for the
    /// ordinary English inflections people write it with. `fucking` and
    /// `shitting` are the same word as `fuck` and `shit`, and listing every
    /// inflection separately is how a wordlist rots; stripping a small, fixed
    /// set of suffixes keeps the list to base forms.
    ///
    /// Matching stays whole-token throughout: a suffix is only removed from
    /// the *end* of a complete run, and what remains still has to equal a
    /// blocklisted word outright. `Dickens` loses its `s` and becomes
    /// `dicken`, which matches nothing, and `cockpit` has no suffix to lose
    /// at all.
    private static func matchesBlockedWord(_ candidate: String) -> Bool {
        if blockedWords.contains(candidate) { return true }
        for suffix in inflectionSuffixes where candidate.count > suffix.count {
            let stem = String(candidate.dropLast(suffix.count))
            guard candidate.hasSuffix(suffix) else { continue }
            if blockedWords.contains(stem) { return true }
            // `shitting`, `fagged`: the final consonant is doubled before the
            // suffix, so the stem is one letter shorter still.
            if let last = stem.last, stem.dropLast().last == last,
               blockedWords.contains(String(stem.dropLast())) {
                return true
            }
        }
        return false
    }

    // MARK: - Normalization

    /// Leetspeak stand-ins that matter in practice. `1` is mapped to `i`
    /// only (not `l`) to keep the substitution unambiguous; extend this if
    /// a real evasion needs the other reading.
    private static let leetMap: [Character: Character] = [
        "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "@": "a", "$": "s"
    ]

    /// Lowercases, strips diacritics, applies the leetspeak map, then splits
    /// on every character that is not a letter or digit. Punctuation and
    /// whitespace are deliberately treated the same way here: both are used
    /// to break up a word to dodge a filter, and neither is needed to tell
    /// real word boundaries apart once matching is whole-token, not
    /// substring.
    private static func tokenize(_ text: String) -> [String] {
        let folded = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
        var substituted = ""
        substituted.reserveCapacity(folded.count)
        for character in folded {
            substituted.append(leetMap[character] ?? character)
        }
        return substituted
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    // MARK: - Wordlist
    //
    // Deliberately modest: a few dozen unambiguous slurs and explicit
    // sexual/violent terms, not an exhaustive scrape. Matching is whole-word
    // (see `tokenize`/`isObjectionable`), so entries do not need to dodge
    // common English substrings themselves — "rape" is safe to list because
    // "grape" and "therapist" never reach it as anything but a whole,
    // unrelated token. Edit this list in place; nothing else in the file
    // needs to change to add or remove an entry.
    private static let blockedWords: Set<String> = [
        // Racial / ethnic slurs
        "nigger", "nigga", "chink", "gook", "spic", "kike", "wetback", "beaner",
        // Homophobic / transphobic slurs
        "faggot", "fag", "tranny", "dyke",
        // Ableist slur
        "retard", "retarded",
        // Explicit sexual terms
        "cunt", "whore", "slut", "cock", "dick", "pussy",
        // Sexual violence / predation
        "rape", "rapist", "molest", "pedophile", "pedo",
        // Violence / hate
        "lynch", "genocide",
        // General profanity
        "fuck", "shit", "bitch", "bastard", "asshole"
    ]

    /// Suffixes stripped by ``matchesBlockedWord``. Kept short and
    /// unambiguous on purpose: every entry added here is a new chance to turn
    /// an innocent word into a blocklisted one, and `ChirpTests/TextFilterTests`
    /// guards that direction.
    private static let inflectionSuffixes = ["s", "es", "ed", "ing", "er", "ers", "in", "y"]

    private static let longestBlockedWordLength = blockedWords.map(\.count).max() ?? 0

    /// The cap on how much text one window may join before we stop growing
    /// it. The longest blocklisted word plus the longest suffix, because a
    /// run has to survive long enough to have its suffix taken off.
    private static let longestCandidateLength =
        longestBlockedWordLength + (inflectionSuffixes.map(\.count).max() ?? 0)
}
