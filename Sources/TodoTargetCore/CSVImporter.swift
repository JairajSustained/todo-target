import Foundation

public enum CSVImportError: Error, Equatable, Sendable {
    case missingHeader
    case missingColumn(String)
    case emptyTitle(line: Int)
    case invalidURL(line: Int)
}

public enum CSVImporter {
    /// Parses a list: columns `group`, `title`, optional `url` (http or https only).
    public static func parse(_ text: String) throws -> [ListItem] {
        let records = tokenize(text).filter { rec in rec.fields.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
        guard let header = records.first else { throw CSVImportError.missingHeader }

        let names = header.fields.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        guard let groupCol = names.firstIndex(of: "group") else { throw CSVImportError.missingColumn("group") }
        guard let titleCol = names.firstIndex(of: "title") else { throw CSVImportError.missingColumn("title") }
        let urlCol = names.firstIndex(of: "url")

        func field(_ rec: Record, _ i: Int?) -> String {
            guard let i, i < rec.fields.count else { return "" }
            return rec.fields[i].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var items: [ListItem] = []
        for rec in records.dropFirst() {
            let title = field(rec, titleCol)
            if title.isEmpty { throw CSVImportError.emptyTitle(line: rec.line) }
            var url: URL?
            let raw = field(rec, urlCol)
            if !raw.isEmpty {
                guard let u = URL(string: raw), let scheme = u.scheme?.lowercased(),
                      scheme == "http" || scheme == "https",
                      let host = u.host, !host.isEmpty else { throw CSVImportError.invalidURL(line: rec.line) }
                url = u
            }
            items.append(ListItem(group: field(rec, groupCol), title: title, url: url))
        }
        return items
    }

    private struct Record { var fields: [String]; var line: Int }

    /// RFC 4180 tokenizer. Accepts LF, CRLF and CR. `line` is the 1-based line where a record starts.
    private static func tokenize(_ input: String) -> [Record] {
        var chars = Array(input)
        if chars.first == "\u{FEFF}" { chars.removeFirst() }

        var records: [Record] = []
        var fields: [String] = []
        var field = ""
        var inQuotes = false
        var line = 1
        var recordLine = 1
        var i = 0

        func endRecord() {
            fields.append(field)
            records.append(Record(fields: fields, line: recordLine))
            fields = []; field = ""
        }

        while i < chars.count {
            let c = chars[i]
            let isNewline = c == "\n" || c == "\r" || c == "\r\n"
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 } else { inQuotes = false }
                } else {
                    if isNewline { line += 1 }
                    field.append(c == "\r\n" || c == "\r" ? "\n" : c)
                }
            } else if c == "\"" && field.isEmpty {
                inQuotes = true
            } else if c == "," {
                fields.append(field); field = ""
            } else if isNewline {
                endRecord()
                line += 1
                recordLine = line
            } else {
                field.append(c)
            }
            i += 1
        }
        if !field.isEmpty || !fields.isEmpty { endRecord() }
        return records
    }
}

extension Goal {
    /// Replaces the list. The position resets to 0 unless `keepPosition`; it is clamped to the new length.
    public mutating func replaceList(_ items: [ListItem], keepPosition: Bool) {
        self.items = items
        position = keepPosition ? min(max(position, 0), items.count) : 0
    }
}
