//
//  WordFilter.swift
//  Intervally
//

import Foundation

/// Keeps curse words and slurs out of the names a preset gives its phases, which the run
/// screen and the Lock Screen show and the voice coach says aloud. Strict on purpose: when in
/// doubt it refuses, so a few innocent names go too ("Peacock", "Scrap"), and a refused name
/// keeps the phase's own ("Work", `PhaseLabel.cleaned`).
///
/// Every word is caught however it's dressed: any case; letters from other alphabets that
/// look the same, and fancy or full-width ones; digits and signs for letters ("sh1t", "a$$",
/// a 1 read as both i and l); letters spaced or punctuated apart ("f.u.c.k"); and letters
/// stretched ("fuuuck"). `anywhere` words are caught inside other words too. The few in
/// `wholeWords` sit inside common ones ("ass" in Class, "hell" in Hello): those are caught
/// as a word of their own, spaced, stretched or with an s, and their compounds are on
/// `anywhere` ("dumbass").
///
/// The words are kept in ROT13, so the list doesn't read as itself in the source.
enum WordFilter {
    /// Whether `name` is free of every word on the lists.
    static func allows(_ name: String) -> Bool {
        let text = String(name.precomposedStringWithCompatibilityMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
            .map { character in
                let character = lookalikes[character] ?? character
                // A 1, ! or | could be an i or an l: kept as a 1, which the patterns take as either.
                return "!|".contains(character) ? "1" : swaps[character] ?? character
            })
        return !contains(text)
    }

    private static func contains(_ text: String) -> Bool {
        let letters = text.filter(isLetter)
        if anywherePatterns.contains(where: { letters.contains($0) }) { return true }
        let tokens = text.split { !isLetter($0) }.map(String.init) + [letters]
        return tokens.contains { token in wholeWordPatterns.contains { token.wholeMatch(of: $0) != nil } }
    }

    /// Each word with every letter allowed to repeat ("f+u+c+k+"), so a stretched one is
    /// caught ("fuuuck") and a short one isn't found in a word that merely shares letters
    /// ("b+o+o+b+" needs both o's, so "Bob" passes). An i or an l may also be a 1, each on
    /// its own, so a word with both is caught however they're written.
    nonisolated(unsafe) private static let anywherePatterns: [Regex<Substring>] = anywhere.map(stretchable)
    /// The same, matched against a whole word, with an s or es allowed after it.
    nonisolated(unsafe) private static let wholeWordPatterns: [Regex<Substring>] = wholeWords.map {
        try! Regex("^" + pattern($0) + "(?:e?s+)?$", as: Substring.self)
    }

    private static func stretchable(_ word: String) -> Regex<Substring> {
        try! Regex(pattern(word), as: Substring.self)
    }

    private static func pattern(_ word: String) -> String {
        word.map { letter in
            switch letter {
            case "i": "[i1]+"
            case "l": "[l1]+"
            default: "\(letter)+"
            }
        }.joined()
    }

    /// Caught wherever they appear, even inside another word.
    static let anywhere: [String] = [
        "shpx", "shx", "shd", "spx", "sphx", "cuhx", "cuhpx", "fuvg", "fulg", "ovgpu", "ovngpu",
        "ovbgpu", "ogpu", "phag", "nffubyr", "nffung", "nffjvcr", "qhzonff", "wnpxnff", "onqnff",
        "fznegnff", "xvpxnff", "sngnff", "onfgneq", "juber", "fyhg", "gjng", "jnax", "wvmm",
        "chffl", "cvff", "fxnax", "cbea", "pbpx", "qvpx", "qnza", "penc", "obyybpx", "ohttre",
        "cevpx", "qbhpur", "zvys", "qvyqb", "obbo", "gvgg", "phz", "avtt", "avtn", "snt", "qlxr",
        "xvxr", "tbbx", "cnxv", "anmv", "uvgyre", "ergneq", "genaal", "jrgonpx", "ornare",
        "arteb", "fcnm", "xxx", "ubzb", "puvax"
    ].map(rot13)

    /// Caught only standing alone, spaced, stretched, or with an s or es: each sits inside
    /// common words ("class", "title", "shoe", "spice", "raccoon", "grape", "hello").
    static let wholeWords: [String] = [
        "nff", "nmm", "nefr", "gvg", "ub", "ubr", "fcvp", "pbba", "encr", "uryy", "jgs", "fgsh",
        "szy", "bzst"
    ].map(rot13)

    /// A letter, or a 1 standing in for one.
    private static func isLetter(_ character: Character) -> Bool {
        (character >= "a" && character <= "z") || character == "1"
    }

    /// The digits and signs that stand in for letters (a 1, ! or | by `pattern`).
    private static let swaps: [Character: Character] = [
        "0": "o", "3": "e", "4": "a", "@": "a", "5": "s", "$": "s", "7": "t", "+": "t",
        "8": "b", "9": "g", "6": "g", "(": "c", "<": "c", "€": "e", "¢": "c", "£": "l",
    ]

    /// Letters from other alphabets drawn like Latin ones: Cyrillic and Greek.
    private static let lookalikes: [Character: Character] = [
        "а": "a", "в": "b", "е": "e", "ё": "e", "к": "k", "м": "m", "н": "h", "о": "o", "р": "p", "с": "c",
        "т": "t", "у": "y", "х": "x", "і": "i", "ї": "i", "ј": "j", "ѕ": "s", "ԁ": "d", "ɡ": "g", "һ": "h",
        "α": "a", "β": "b", "ε": "e", "ι": "i", "κ": "k", "ν": "v", "ο": "o", "ρ": "p", "τ": "t", "υ": "u",
        "χ": "x", "ϲ": "c",
    ]

    static func rot13(_ text: String) -> String {
        String(text.map { character in
            guard let ascii = character.asciiValue, character.isLetter else { return character }
            let base: UInt8 = character.isUppercase ? 65 : 97
            return Character(UnicodeScalar((ascii - base + 13) % 26 + base))
        })
    }
}
