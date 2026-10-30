//
//  SwiftSource.swift
//  IntervallyPhoneTests
//

import Foundation

/// Swift source read as tokens, enough to tell what a SwiftUI modifier hangs on and what a
/// row's actions do. Comments and the insides of strings drop out, brackets pair up, and
/// `#if` lines go, so a chain of modifiers reads straight through them. Not a parser: it
/// reads the app's own views, written the way they are, for `PresenterGuardTests`.
struct SwiftSource {
    struct Token: Equatable {
        enum Kind: Equatable {
            case word, string, symbol
        }

        let kind: Kind
        /// The word or the symbol; a string's text without its quotes.
        let text: String
        let line: Int
    }

    let tokens: [Token]
    /// Each bracket's partner, both ways: `(` and `)`, `[` and `]`, `{` and `}`.
    let partner: [Int: Int]

    init(_ text: String) {
        let c = Array(text)
        var tokens: [Token] = []
        var line = 1
        var lineStart = true
        var i = 0
        while i < c.count {
            let char = c[i]
            if char == "\n" {
                line += 1
                lineStart = true
                i += 1
            } else if char.isWhitespace {
                i += 1
            } else if char == "/", i + 1 < c.count, c[i + 1] == "/" {
                while i < c.count, c[i] != "\n" { i += 1 }
            } else if char == "/", i + 1 < c.count, c[i + 1] == "*" {
                i = Self.endOfComment(c, from: i, line: &line)
            } else if char == "#", lineStart, Self.isDirective(c, at: i) {
                while i < c.count, c[i] != "\n" { i += 1 }
            } else if Self.startsString(c, at: i) {
                let start = i
                let startLine = line
                i = Self.endOfString(c, from: i, line: &line)
                tokens.append(Token(kind: .string, text: Self.contents(c, from: start, to: i), line: startLine))
                lineStart = false
            } else if char.isLetter || char.isNumber || char == "_" {
                let start = i
                while i < c.count, c[i].isLetter || c[i].isNumber || c[i] == "_"
                    // A decimal point, as in 0.5; not a range's dots or a member.
                    || (c[i] == "." && c[start].isNumber && i + 1 < c.count && c[i + 1].isNumber) {
                    i += 1
                }
                tokens.append(Token(kind: .word, text: String(c[start..<i]), line: line))
                lineStart = false
            } else {
                tokens.append(Token(kind: .symbol, text: String(char), line: line))
                lineStart = false
                i += 1
            }
        }
        self.tokens = tokens

        var partner: [Int: Int] = [:]
        var open: [Int] = []
        for (index, token) in tokens.enumerated() where token.kind == .symbol {
            switch token.text {
            case "(", "[", "{":
                open.append(index)
            case ")", "]", "}":
                if let last = open.popLast() {
                    partner[last] = index
                    partner[index] = last
                }
            default:
                break
            }
        }
        self.partner = partner
    }

    // MARK: - Reading the text

    /// `#if`, `#elseif`, `#else` and `#endif`. `#Preview` and `#filePath` are code.
    private static func isDirective(_ c: [Character], at start: Int) -> Bool {
        var end = start + 1
        while end < c.count, c[end].isLetter { end += 1 }
        return ["if", "elseif", "else", "endif"].contains(String(c[(start + 1)..<end]))
    }

    /// A quote, or the hashes of a raw string before one.
    private static func startsString(_ c: [Character], at start: Int) -> Bool {
        var i = start
        while i < c.count, c[i] == "#" { i += 1 }
        return i < c.count && c[i] == "\""
    }

    /// Past the end of a block comment, which may hold others.
    private static func endOfComment(_ c: [Character], from start: Int, line: inout Int) -> Int {
        var depth = 0
        var i = start
        while i + 1 < c.count {
            if c[i] == "/", c[i + 1] == "*" {
                depth += 1
                i += 2
            } else if c[i] == "*", c[i + 1] == "/" {
                depth -= 1
                i += 2
                if depth == 0 { return i }
            } else {
                if c[i] == "\n" { line += 1 }
                i += 1
            }
        }
        return c.count
    }

    /// Past the end of the string that starts at `start`: one line or three quotes, raw or
    /// not. An interpolation is read as code, so a string inside one can hold a quote or a
    /// bracket without ending anything.
    private static func endOfString(_ c: [Character], from start: Int, line: inout Int) -> Int {
        let (hashes, quotes) = delimiters(c, at: start)
        var i = start + hashes + quotes
        while i < c.count {
            if c[i] == "\\", hashCount(c, from: i + 1) == hashes {
                let next = i + 1 + hashes
                i = next < c.count && c[next] == "(" ? endOfInterpolation(c, from: next, line: &line) : next + 1
            } else if c[i] == "\"", closes(c, at: i, hashes: hashes, quotes: quotes) {
                return i + quotes + hashes
            } else {
                if c[i] == "\n" { line += 1 }
                i += 1
            }
        }
        return c.count
    }

    /// Past the bracket that closes the interpolation opened at `open`.
    private static func endOfInterpolation(_ c: [Character], from open: Int, line: inout Int) -> Int {
        var depth = 0
        var i = open
        while i < c.count {
            if startsString(c, at: i) {
                i = endOfString(c, from: i, line: &line)
                continue
            }
            switch c[i] {
            case "(": depth += 1
            case ")":
                depth -= 1
                if depth == 0 { return i + 1 }
            case "\n": line += 1
            default: break
            }
            i += 1
        }
        return c.count
    }

    /// A string's hashes and quotes: `"`, `"""`, `#"` and so on.
    private static func delimiters(_ c: [Character], at start: Int) -> (hashes: Int, quotes: Int) {
        let hashes = hashCount(c, from: start)
        let quote = start + hashes
        let triple = quote + 2 < c.count && c[quote + 1] == "\"" && c[quote + 2] == "\""
        return (hashes, triple ? 3 : 1)
    }

    private static func hashCount(_ c: [Character], from start: Int) -> Int {
        var i = start
        while i < c.count, c[i] == "#" { i += 1 }
        return i - start
    }

    private static func closes(_ c: [Character], at i: Int, hashes: Int, quotes: Int) -> Bool {
        guard i + quotes + hashes <= c.count else { return false }
        return c[i..<(i + quotes)].allSatisfy { $0 == "\"" } && c[(i + quotes)..<(i + quotes + hashes)].allSatisfy { $0 == "#" }
    }

    private static func contents(_ c: [Character], from start: Int, to end: Int) -> String {
        let (hashes, quotes) = delimiters(c, at: start)
        let from = start + hashes + quotes
        let to = end - hashes - quotes
        return from < to ? String(c[from..<to]) : ""
    }

    // MARK: - Reading the code

    /// Whether the token at `index` is the word or symbol `text`. A string never is.
    func has(_ text: String, at index: Int) -> Bool {
        tokens.indices.contains(index) && tokens[index].kind != .string && tokens[index].text == text
    }

    private func isWord(at index: Int) -> Bool {
        tokens.indices.contains(index) && tokens[index].kind == .word
    }

    /// Each `.name(…)` or `.name { … }` called, as the index of its name.
    func calls(of names: Set<String>) -> [Int] {
        tokens.indices.filter { i in
            isWord(at: i) && names.contains(tokens[i].text) && has(".", at: i - 1) && (has("(", at: i + 1) || has("{", at: i + 1))
        }
    }

    /// The word a chain of modifiers starts from, for the call named at `name`: `Section` in
    /// `Section { … } header: { … }.listRowBackground(.clear).alert(…)`. Nil when it starts
    /// from anything but a word, such as a bracket or an operator.
    func chainStart(ofCallAt name: Int) -> Int? {
        var i = name - 2
        while i >= 0 {
            let token = tokens[i]
            if token.kind == .symbol, [")", "]", "}"].contains(token.text) {
                guard let open = partner[i] else { return nil }
                i = open - 1
                // A labelled trailing closure, `} header: {`: on to the closure before it.
                if token.text == "}", has(":", at: i), isWord(at: i - 1), has("}", at: i - 2) {
                    i -= 2
                }
            } else if has("?", at: i) || has("!", at: i) {
                i -= 1
            } else if token.kind == .word {
                guard has(".", at: i - 1) else { return i }
                i -= 2
            } else {
                return nil
            }
        }
        return nil
    }

    /// The tokens of a call's arguments and trailing closures, labelled ones included.
    func extent(ofCallAt name: Int) -> ClosedRange<Int>? {
        var end = name
        var i = name + 1
        if has("(", at: i), let close = partner[i] {
            end = close
            i = close + 1
        }
        while has("{", at: i), let close = partner[i] {
            end = close
            i = close + 1
            if isWord(at: i), has(":", at: i + 1), has("{", at: i + 2) { i += 2 }
        }
        return end > name ? (name + 1)...end : nil
    }

    /// The tokens inside the call's brackets, when it has them.
    func arguments(ofCallAt name: Int) -> ClosedRange<Int>? {
        guard has("(", at: name + 1), let close = partner[name + 1], close > name + 2 else { return nil }
        return (name + 2)...(close - 1)
    }

    /// Each `struct` with what it conforms to and the tokens of its body.
    func structs() -> [(name: String, conformances: Set<String>, body: ClosedRange<Int>)] {
        tokens.indices.compactMap { i in
            guard has("struct", at: i), isWord(at: i + 1) else { return nil }
            var brace = i + 2
            var conformances: Set<String> = []
            while tokens.indices.contains(brace), !has("{", at: brace) {
                if isWord(at: brace) { conformances.insert(tokens[brace].text) }
                brace += 1
            }
            guard let close = partner[brace] else { return nil }
            return (tokens[i + 1].text, conformances, brace...close)
        }
    }

    /// Each function declared in an `extension View`, with the tokens of its body.
    func viewExtensionFunctions() -> [(name: String, body: ClosedRange<Int>)] {
        var found: [(name: String, body: ClosedRange<Int>)] = []
        for i in tokens.indices where has("extension", at: i) && has("View", at: i + 1) {
            var brace = i + 2
            while tokens.indices.contains(brace), !has("{", at: brace) { brace += 1 }
            guard let close = partner[brace] else { continue }
            var j = brace + 1
            while j < close {
                guard has("func", at: j), isWord(at: j + 1) else {
                    j += 1
                    continue
                }
                // The body is the first brace after the signature, whose brackets may hold
                // closures of their own, as defaults.
                var body = j + 2
                while body < close, !has("{", at: body) {
                    body = has("(", at: body) ? (partner[body] ?? body) + 1 : body + 1
                }
                guard let end = partner[body] else { break }
                found.append((tokens[j + 1].text, body...end))
                j = end + 1
            }
        }
        return found
    }

    /// The first word of a view's `body`.
    func bodyStart(in range: ClosedRange<Int>) -> String? {
        guard let declaration = range.first(where: { has("var", at: $0) && has("body", at: $0 + 1) && has(":", at: $0 + 2) }) else {
            return nil
        }
        var brace = declaration + 3
        while brace < range.upperBound, !has("{", at: brace) { brace += 1 }
        let first = has("return", at: brace + 1) ? brace + 2 : brace + 1
        return isWord(at: first) ? tokens[first].text : nil
    }

    /// Whether the tokens in `range` call one of `presenters`, or apply one of `modifiers`
    /// with `modifier(…)`.
    func presents(in range: ClosedRange<Int>, presenters: Set<String>, modifiers: Set<String>) -> Bool {
        range.contains { i in
            guard isWord(at: i), has("(", at: i + 1) else { return false }
            if presenters.contains(tokens[i].text) { return true }
            return tokens[i].text == "modifier" && isWord(at: i + 2) && modifiers.contains(tokens[i + 2].text)
        }
    }
}

/// Something a rule found, and where.
struct SourceFinding: Equatable, CustomStringConvertible {
    let file: String
    let line: Int
    let what: String

    var description: String { "\(file):\(line): \(what)" }
}

/// The views of the app, read once, with what the rules need from all of them together: the
/// app's own presenting modifiers, and its views whose body is a `Section`.
struct ViewSources {
    struct File {
        let path: String
        let source: SwiftSource
    }

    /// The system's modifiers that present something over the screen.
    static let systemPresenters: Set<String> = [
        "alert", "confirmationDialog", "sheet", "fullScreenCover", "popover", "fileImporter", "fileExporter",
    ]
    /// Inside a list or form, SwiftUI copies a modifier on one of these to every row in it.
    static let systemRowCopiers: Set<String> = ["Section", "ForEach"]

    let files: [File]
    /// The system's presenters, and every `extension View` function that calls one.
    let presenters: Set<String>
    /// `ViewModifier`s that present, applied with `modifier(…)`.
    let presentingModifiers: Set<String>
    /// `Section` and `ForEach`, and every view whose body is one of them.
    let rowCopiers: Set<String>

    init(files: [File]) {
        self.files = files
        var presenters = Self.systemPresenters
        var modifiers: Set<String> = []
        var rowCopiers = Self.systemRowCopiers
        // Until nothing changes: a wrapper can wrap another wrapper.
        var changed = true
        while changed {
            changed = false
            for file in files {
                let source = file.source
                for declared in source.structs() {
                    if declared.conformances.contains("ViewModifier"), !modifiers.contains(declared.name),
                       source.presents(in: declared.body, presenters: presenters, modifiers: modifiers) {
                        modifiers.insert(declared.name)
                        changed = true
                    }
                    if declared.conformances.contains("View"), !rowCopiers.contains(declared.name),
                       let first = source.bodyStart(in: declared.body), rowCopiers.contains(first) {
                        rowCopiers.insert(declared.name)
                        changed = true
                    }
                }
                for function in source.viewExtensionFunctions() where !presenters.contains(function.name) {
                    if source.presents(in: function.body, presenters: presenters, modifiers: modifiers) {
                        presenters.insert(function.name)
                        changed = true
                    }
                }
            }
        }
        self.presenters = presenters
        self.presentingModifiers = modifiers
        self.rowCopiers = rowCopiers
    }

    /// Every Swift file under `folders`, which are relative to `root`.
    init(folders: [String], under root: URL) throws {
        var files: [File] = []
        for folder in folders {
            let base = root.appendingPathComponent(folder)
            let paths = (FileManager.default.subpaths(atPath: base.path) ?? []).filter { $0.hasSuffix(".swift") }.sorted()
            for path in paths {
                let text = try String(contentsOf: base.appendingPathComponent(path), encoding: .utf8)
                files.append(File(path: "\(folder)/\(path)", source: SwiftSource(text)))
            }
        }
        self.init(files: files)
    }

    /// The files that call `.name`.
    func files(calling name: String) -> [String] {
        files.filter { !$0.source.calls(of: [name]).isEmpty }.map(\.path)
    }

    // MARK: - The rules

    /// Presenters hung on a `Section`, a `ForEach` or a view whose body is one: each row
    /// gets a copy, and the copies race to present and close each other.
    func presentersOnRows() -> [SourceFinding] {
        files.flatMap { file in
            let source = file.source
            return source.calls(of: presenters.union(["modifier"])).compactMap { name -> SourceFinding? in
                let called = source.tokens[name].text
                if called == "modifier" {
                    guard source.tokens.indices.contains(name + 2), presentingModifiers.contains(source.tokens[name + 2].text) else {
                        return nil
                    }
                }
                guard let start = source.chainStart(ofCallAt: name), rowCopiers.contains(source.tokens[start].text) else { return nil }
                return SourceFinding(file: file.path, line: source.tokens[name].line, what: ".\(called) on \(source.tokens[start].text)")
            }
        }
    }

    /// Swipe actions and menus that delete outright rather than ask, and the system's swipe
    /// to delete, which asks nothing.
    func rowActionsThatDelete() -> [SourceFinding] {
        files.flatMap { file in
            let source = file.source
            let direct = source.calls(of: ["swipeActions", "contextMenu"]).compactMap { name -> SourceFinding? in
                guard let extent = source.extent(ofCallAt: name),
                      let call = extent.first(where: { i in
                          source.tokens[i].kind == .word && source.tokens[i].text.hasPrefix("delete") && source.has("(", at: i + 1)
                      }) else { return nil }
                return SourceFinding(
                    file: file.path, line: source.tokens[call].line,
                    what: "\(source.tokens[call].text)( in .\(source.tokens[name].text)"
                )
            }
            let system = source.calls(of: ["onDelete"]).map { name in
                SourceFinding(file: file.path, line: source.tokens[name].line, what: ".onDelete")
            }
            return direct + system
        }
    }

    /// Destructive buttons in swipe actions. SwiftUI takes the row off the list as one is
    /// tapped, so one that only asks loses the row on Cancel, and the delete that follows
    /// asks the list to remove it again, which crashes it.
    func destructiveSwipes() -> [SourceFinding] {
        files.flatMap { file in
            let source = file.source
            return source.calls(of: ["swipeActions"]).flatMap { name -> [SourceFinding] in
                guard let extent = source.extent(ofCallAt: name) else { return [] }
                return extent.filter { source.has("destructive", at: $0) && source.has(".", at: $0 - 1) }.map { i in
                    SourceFinding(file: file.path, line: source.tokens[i].line, what: "destructive role in .swipeActions")
                }
            }
        }
    }

    /// Swipe actions holding a Delete that a full swipe would run without its tap.
    func fullSwipeDeletes() -> [SourceFinding] {
        files.flatMap { file in
            let source = file.source
            return source.calls(of: ["swipeActions"]).compactMap { name -> SourceFinding? in
                guard let extent = source.extent(ofCallAt: name),
                      extent.contains(where: { i in
                          (source.tokens[i].kind == .string && source.tokens[i].text == "Delete")
                              || (source.has("destructive", at: i) && source.has(".", at: i - 1))
                      }) else { return nil }
                let noFullSwipe = source.arguments(ofCallAt: name)?.contains { i in
                    source.has("allowsFullSwipe", at: i) && source.has(":", at: i + 1) && source.has("false", at: i + 2)
                } ?? false
                return noFullSwipe ? nil : SourceFinding(file: file.path, line: source.tokens[name].line, what: "full swipe runs Delete")
            }
        }
    }
}
