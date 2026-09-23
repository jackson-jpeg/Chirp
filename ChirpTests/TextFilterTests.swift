import XCTest
@testable import Chirp

@MainActor
final class TextFilterTests: XCTestCase {

    private static let suiteName = "com.chirpchirp.tests.textfilter"

    /// A defaults suite wiped clean, so every test starts from empty state.
    private func makeFreshDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: Self.suiteName)!
        defaults.removePersistentDomain(forName: Self.suiteName)
        return defaults
    }

    // MARK: - Enabled state

    func testEnabledByDefault() {
        let defaults = makeFreshDefaults()
        let filter = TextFilter(defaults: defaults)
        XCTAssertTrue(filter.isEnabled, "The filter must protect people out of the box")
    }

    func testTogglePersistsAcrossRelaunch() {
        let defaults = makeFreshDefaults()
        let filter = TextFilter(defaults: defaults)

        filter.setEnabled(false)
        XCTAssertFalse(filter.isEnabled)

        // A fresh instance models an app relaunch.
        let reloaded = TextFilter(defaults: defaults)
        XCTAssertFalse(reloaded.isEnabled, "Disabling must persist")

        reloaded.setEnabled(true)
        let reloadedAgain = TextFilter(defaults: defaults)
        XCTAssertTrue(reloadedAgain.isEnabled, "Re-enabling must persist")
    }

    func testOnChangeFiresWithNewValue() {
        let defaults = makeFreshDefaults()
        let filter = TextFilter(defaults: defaults)
        var observed: [Bool] = []
        filter.onChange = { observed.append($0) }

        filter.setEnabled(false)
        filter.setEnabled(true)
        // Setting to the same value again must not fire a redundant change.
        filter.setEnabled(true)

        XCTAssertEqual(observed, [false, true])
    }

    func testDisabledFilterClassifiesNothing() {
        let defaults = makeFreshDefaults()
        let filter = TextFilter(defaults: defaults)
        filter.setEnabled(false)

        XCTAssertFalse(filter.isObjectionable("fuck you"))
        XCTAssertFalse(filter.isObjectionable("n1gg3r"))
        XCTAssertFalse(filter.isObjectionable("f u c k"))
    }

    // MARK: - Plain matches

    func testPlainSlursAndProfanityAreFlagged() {
        let defaults = makeFreshDefaults()
        let filter = TextFilter(defaults: defaults)

        let flagged = [
            "nigger", "nigga", "chink", "gook", "spic", "kike", "wetback", "beaner",
            "faggot", "fag", "tranny", "dyke",
            "retard", "retarded",
            "cunt", "whore", "slut", "cock", "dick", "pussy",
            "rape", "rapist", "molest", "pedophile", "pedo",
            "lynch", "genocide",
            "fuck", "shit", "bitch", "bastard", "asshole"
        ]
        for word in flagged {
            XCTAssertTrue(filter.isObjectionable(word), "\"\(word)\" must be flagged")
            XCTAssertTrue(filter.isObjectionable("hey \(word) there"), "\"\(word)\" must be flagged mid-sentence")
        }
    }

    func testMatchingIsCaseInsensitive() {
        let defaults = makeFreshDefaults()
        let filter = TextFilter(defaults: defaults)

        XCTAssertTrue(filter.isObjectionable("FUCK"))
        XCTAssertTrue(filter.isObjectionable("FuCk you"))
        XCTAssertTrue(filter.isObjectionable("NiGgEr"))
    }

    func testMatchingIsDiacriticInsensitive() {
        let defaults = makeFreshDefaults()
        let filter = TextFilter(defaults: defaults)

        XCTAssertTrue(filter.isObjectionable("fück"))
        XCTAssertTrue(filter.isObjectionable("bïtch please"))
        XCTAssertTrue(filter.isObjectionable("shît"))
    }

    // MARK: - Evasion: internal punctuation / spacing

    func testInternalPunctuationEvasionIsCaught() {
        let defaults = makeFreshDefaults()
        let filter = TextFilter(defaults: defaults)

        XCTAssertTrue(filter.isObjectionable("f.u.c.k"))
        XCTAssertTrue(filter.isObjectionable("f-u-c-k"))
        XCTAssertTrue(filter.isObjectionable("f*u*c*k off"))
        XCTAssertTrue(filter.isObjectionable("n.i.g.g.e.r"))
    }

    func testInternalSpacingEvasionIsCaught() {
        let defaults = makeFreshDefaults()
        let filter = TextFilter(defaults: defaults)

        XCTAssertTrue(filter.isObjectionable("f u c k"))
        XCTAssertTrue(filter.isObjectionable("you are a b i t c h"))
        XCTAssertTrue(filter.isObjectionable("c u n t"))
    }

    // MARK: - Evasion: leetspeak

    func testLeetspeakSubstitutionsAreCaught() {
        let defaults = makeFreshDefaults()
        let filter = TextFilter(defaults: defaults)

        XCTAssertTrue(filter.isObjectionable("wh0re"), "0 -> o")
        XCTAssertTrue(filter.isObjectionable("n1gger"), "1 -> i")
        XCTAssertTrue(filter.isObjectionable("fuck3r sh1t"), "3 -> e")
        XCTAssertTrue(filter.isObjectionable("f4ggot"), "4 -> a")
        XCTAssertTrue(filter.isObjectionable("5lut"), "5 -> s")
        XCTAssertTrue(filter.isObjectionable("@sshole"), "@ -> a")
        XCTAssertTrue(filter.isObjectionable("$lut"), "$ -> s")
        XCTAssertTrue(filter.isObjectionable("b1tch"), "combined 1 -> i")
    }

    func testLeetspeakCombinedWithCaseAndPunctuation() {
        let defaults = makeFreshDefaults()
        let filter = TextFilter(defaults: defaults)

        XCTAssertTrue(filter.isObjectionable("N1GG3R"))
        XCTAssertTrue(filter.isObjectionable("f.u.c.k1ng"))
    }

    // MARK: - False positives (the hard part)

    func testInnocentWordsContainingSlurSubstringsPassClean() {
        let defaults = makeFreshDefaults()
        let filter = TextFilter(defaults: defaults)

        let innocent = [
            "Scunthorpe",
            "classic",
            "assignment",
            "analysis",
            "bass",
            "grape",
            "shuttlecock",
            "Dickens",
            "cockpit",
            "therapist",
            "password"
        ]
        for word in innocent {
            XCTAssertFalse(filter.isObjectionable(word), "\"\(word)\" must pass clean")
            XCTAssertFalse(
                filter.isObjectionable("I read about \(word) yesterday"),
                "\"\(word)\" must pass clean mid-sentence"
            )
        }
    }

    func testInnocentSentencesPassClean() {
        let defaults = makeFreshDefaults()
        let filter = TextFilter(defaults: defaults)

        XCTAssertFalse(filter.isObjectionable("Let's meet at the cockpit display in the museum."))
        XCTAssertFalse(filter.isObjectionable("My therapist recommended a book on classic literature."))
        XCTAssertFalse(filter.isObjectionable("Grape juice and bass fishing, my favorite weekend."))
        XCTAssertFalse(filter.isObjectionable("Reset your password before the assignment is due."))
        XCTAssertFalse(filter.isObjectionable("Scunthorpe is a town in England, per Dickens' era maps."))
        XCTAssertFalse(filter.isObjectionable("The shuttlecock analysis was surprisingly thorough."))
        XCTAssertFalse(filter.isObjectionable(""))
        XCTAssertFalse(filter.isObjectionable("Hello, how are you today?"))
    }
}
