import Testing
import Foundation
@testable import TodoTargetCore

@Test func parsesBasicRows() throws {
    let items = try CSVImporter.parse("group,title,url\nTrees,Max Depth,https://x.dev/1\n")
    #expect(items.count == 1)
    #expect(items[0].group == "Trees"); #expect(items[0].title == "Max Depth")
    #expect(items[0].url == URL(string: "https://x.dev/1"))
}

@Test func urlIsOptional() throws {
    let items = try CSVImporter.parse("group,title\nTrees,Max Depth\n")
    #expect(items[0].url == nil)
    let blankUrl = try CSVImporter.parse("group,title,url\nTrees,Max Depth,\n")
    #expect(blankUrl[0].url == nil)
}

@Test func handlesBOMAndCRLF() throws {
    let items = try CSVImporter.parse("\u{FEFF}group,title,url\r\nTrees,A,https://x.dev/1\r\n\r\nTrees,B\r\n")
    #expect(items.map(\.title) == ["A", "B"])
}

@Test func handlesQuotedCommaAndQuote() throws {
    let items = try CSVImporter.parse("group,title\n\"Trees, binary\",\"Say \"\"hi\"\"\"\n")
    #expect(items[0].group == "Trees, binary"); #expect(items[0].title == "Say \"hi\"")
}

@Test func handlesQuotedNewline() throws {
    let items = try CSVImporter.parse("group,title\nA,\"two\nlines\"\n")
    #expect(items.count == 1); #expect(items[0].title == "two\nlines")
}

@Test func lineNumbersCountNewlinesInsideQuotes() {
    #expect(throws: CSVImportError.emptyTitle(line: 4)) { try CSVImporter.parse("group,title\nA,\"two\nlines\"\nB,\n") }
}

@Test func headerIsCaseInsensitiveAndExtraColumnsIgnored() throws {
    let items = try CSVImporter.parse("Notes,TITLE,Group\nn,Hello,G\n")
    #expect(items == [ListItem(group: "G", title: "Hello", url: nil)])
}

@Test func emptyInputHasMissingHeader() {
    #expect(throws: CSVImportError.missingHeader) { try CSVImporter.parse("\n  \n") }
}

@Test func rejectsMissingTitleColumn() {
    #expect(throws: CSVImportError.missingColumn("title")) { try CSVImporter.parse("group,url\nA,https://x.dev\n") }
}

@Test func rejectsEmptyTitle() {
    #expect(throws: CSVImportError.emptyTitle(line: 2)) { try CSVImporter.parse("group,title\nA,  \n") }
}

@Test func rejectsNonWebLinks() {
    for bad in ["javascript:alert(1)", "file:///etc/passwd", "ftp://x", "not a url", "/relative/path"] {
        #expect(throws: CSVImportError.invalidURL(line: 2)) { try CSVImporter.parse("group,title,url\nA,B,\(bad)\n") }
    }
}

@Test func replaceListResetsPositionUnlessKept() {
    let two = [ListItem(group: "g", title: "a"), ListItem(group: "g", title: "b")]
    var g = Goal(name: "x", items: [], position: 5)
    g.replaceList(two, keepPosition: false); #expect(g.position == 0); #expect(g.items == two)
    g.position = 1
    g.replaceList(two, keepPosition: true); #expect(g.position == 1)
    g.position = 9
    g.replaceList(two, keepPosition: true); #expect(g.position == 2)
}
