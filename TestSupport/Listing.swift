//
//  Listing.swift
//  Intervally test support
//

import Foundation

// Compiled into both test bundles: the watch's MetadataTests and the iPhone's
// PhoneMetadataTests read the same listing.

/// One value the listing has you paste, as it writes it down.
struct ListingField: Equatable {
    /// The heading a block sits under, or a table row's first cell.
    let label: String
    let text: String
    /// Apple's limit, written as "(100)" at the end of the label.
    let limit: Int?
    /// The count the listing claims: "(160)" on the line after a block, or after a
    /// table value.
    let statedCount: Int?
    let isBlock: Bool
}

/// Just enough Markdown for `Metadata.md`: fenced blocks under headings, and table rows
/// whose value is in backticks.
enum Listing {
    static func fields(in markdown: String) -> [ListingField] {
        let lines = markdown.components(separatedBy: "\n")
        var fields: [ListingField] = []
        var heading = ""
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if line.hasPrefix("#") {
                heading = line
            } else if line == "```" {
                var body: [String] = []
                index += 1
                while index < lines.count, lines[index] != "```" {
                    body.append(lines[index])
                    index += 1
                }
                let after = index + 1 < lines.count ? lines[index + 1] : ""
                fields.append(ListingField(
                    label: heading, text: body.joined(separator: "\n"),
                    limit: trailingCount(heading), statedCount: leadingCount(after), isBlock: true
                ))
            } else if line.hasPrefix("|"), let field = tableField(line) {
                fields.append(field)
            }
            index += 1
        }
        return fields
    }

    private static func tableField(_ line: String) -> ListingField? {
        let cells = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        guard cells.count >= 2,
              let match = cells[1].firstMatch(of: /^`([^`]+)`(.*)$/) else { return nil }
        return ListingField(
            label: cells[0], text: String(match.1),
            limit: trailingCount(cells[0]), statedCount: trailingCount(String(match.2)), isBlock: false
        )
    }

    private static func trailingCount(_ text: String) -> Int? {
        text.firstMatch(of: /\((\d+)\)\s*$/).flatMap { Int($0.1) }
    }

    private static func leadingCount(_ text: String) -> Int? {
        text.firstMatch(of: /^\((\d+)\)/).flatMap { Int($0.1) }
    }
}
