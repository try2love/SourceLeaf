import Foundation
import Testing

@Test func englishAndChineseLocalizationKeysMatch() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let resources = repositoryRoot.appendingPathComponent("Sources/SourceLeafApp/Resources")
    let english = try String(contentsOf: resources.appendingPathComponent("en.lproj/Localizable.strings"), encoding: .utf8)
    let chinese = try String(contentsOf: resources.appendingPathComponent("zh-Hans.lproj/Localizable.strings"), encoding: .utf8)

    #expect(localizationKeys(in: english) == localizationKeys(in: chinese))
    #expect(localizationKeys(in: chinese).contains("settings.interfaceLanguage"))
    #expect(localizationKeys(in: chinese).contains("prompt.duplicateToEdit"))
}

private func localizationKeys(in source: String) -> Set<String> {
    Set(source.split(separator: "\n").compactMap { line in
        let text = line.trimmingCharacters(in: .whitespaces)
        guard text.hasPrefix("\""), let closingQuote = text.dropFirst().firstIndex(of: "\"") else { return nil }
        return String(text[text.index(after: text.startIndex)..<closingQuote])
    })
}
