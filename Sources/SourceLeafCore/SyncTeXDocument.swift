import Foundation

public struct SyncTeXPDFLocation: Equatable, Sendable {
    public var pageIndex: Int
    public var x: Double
    public var yFromTop: Double
    public var line: Int

    public init(pageIndex: Int, x: Double, yFromTop: Double, line: Int) {
        self.pageIndex = pageIndex
        self.x = x
        self.yFromTop = yFromTop
        self.line = line
    }
}

public struct SyncTeXSourceLocation: Equatable, Sendable {
    public var sourceURL: URL
    public var line: Int

    public init(sourceURL: URL, line: Int) {
        self.sourceURL = sourceURL
        self.line = line
    }
}

public enum SyncTeXError: Error, LocalizedError {
    case invalidDocument
    case decompressionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidDocument: "The SyncTeX index contains no usable source locations."
        case let .decompressionFailed(message): "The SyncTeX index could not be decompressed: \(message)"
        }
    }
}

public struct SyncTeXDocument: Sendable {
    private static let scaledPointsPerPDFPoint = 65_781.76

    private struct Record: Sendable {
        var inputTag: Int
        var line: Int
        var pageIndex: Int
        var horizontal: Int
        var vertical: Int
        var preferredForForwardSearch: Bool
    }

    private var inputs: [Int: URL]
    private var records: [Record]

    public init(contents: String) throws {
        var inputs: [Int: URL] = [:]
        var records: [Record] = []
        var currentPageIndex: Int?
        var insideContent = false
        let recordExpression = try NSRegularExpression(
            pattern: #"^[^0-9-]*([0-9]+),([0-9]+)(?:,[0-9]+)?:(-?[0-9]+),(-?[0-9]+)"#
        )

        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line == "Content:" {
                insideContent = true
                continue
            }
            if !insideContent, line.hasPrefix("Input:") {
                let pieces = line.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
                if pieces.count == 3,
                   let tag = Int(pieces[1]),
                   !pieces[2].isEmpty {
                    inputs[tag] = URL(fileURLWithPath: String(pieces[2])).standardizedFileURL
                }
                continue
            }
            guard insideContent else { continue }
            if line == "Postamble:" { break }
            if line.first == "{", let page = Int(line.dropFirst()) {
                currentPageIndex = max(0, page - 1)
                continue
            }
            if line.first == "}" {
                currentPageIndex = nil
                continue
            }
            guard let currentPageIndex else { continue }
            let range = NSRange(location: 0, length: (line as NSString).length)
            guard let match = recordExpression.firstMatch(in: line, range: range),
                  let inputTag = integer(in: line, match: match, group: 1),
                  let sourceLine = integer(in: line, match: match, group: 2),
                  let horizontal = integer(in: line, match: match, group: 3),
                  let vertical = integer(in: line, match: match, group: 4),
                  inputs[inputTag] != nil else { continue }
            records.append(Record(
                inputTag: inputTag,
                line: sourceLine,
                pageIndex: currentPageIndex,
                horizontal: horizontal,
                vertical: vertical,
                preferredForForwardSearch: line.first == "(" || line.first == "["
            ))
        }
        guard !inputs.isEmpty, !records.isEmpty else { throw SyncTeXError.invalidDocument }
        self.inputs = inputs
        self.records = records
    }

    public static func load(from url: URL, runner: ProcessRunner = ProcessRunner()) async throws -> SyncTeXDocument {
        if url.pathExtension.lowercased() != "gz" {
            return try SyncTeXDocument(contents: String(contentsOf: url, encoding: .utf8))
        }
        let output = try await runner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/gzip"),
            arguments: ["-dc", url.path]
        )
        guard output.exitCode == 0 else {
            throw SyncTeXError.decompressionFailed(output.standardError)
        }
        return try SyncTeXDocument(contents: output.standardOutput)
    }

    public func pdfLocation(sourceURL: URL, line requestedLine: Int) -> SyncTeXPDFLocation? {
        let requestedPath = sourceURL.standardizedFileURL.path
        let matching = records.filter { record in inputs[record.inputTag]?.path == requestedPath }
        guard !matching.isEmpty else { return nil }
        let minimumLineDistance = matching.map { abs($0.line - requestedLine) }.min() ?? 0
        let nearestLines = matching.filter { abs($0.line - requestedLine) == minimumLineDistance }
        let record = nearestLines.first(where: \.preferredForForwardSearch) ?? nearestLines.first
        guard let record else { return nil }
        return SyncTeXPDFLocation(
            pageIndex: record.pageIndex,
            x: Double(record.horizontal) / Self.scaledPointsPerPDFPoint,
            yFromTop: Double(record.vertical) / Self.scaledPointsPerPDFPoint,
            line: record.line
        )
    }

    public func sourceLocation(pageIndex: Int, x: Double, yFromTop: Double) -> SyncTeXSourceLocation? {
        let pageRecords = records.filter { $0.pageIndex == pageIndex }
        let nearest = pageRecords.min { lhs, rhs in
            distanceSquared(from: lhs, x: x, yFromTop: yFromTop)
                < distanceSquared(from: rhs, x: x, yFromTop: yFromTop)
        }
        guard let nearest, let sourceURL = inputs[nearest.inputTag] else { return nil }
        return SyncTeXSourceLocation(sourceURL: sourceURL, line: nearest.line)
    }

    private func distanceSquared(from record: Record, x: Double, yFromTop: Double) -> Double {
        let recordX = Double(record.horizontal) / Self.scaledPointsPerPDFPoint
        let recordY = Double(record.vertical) / Self.scaledPointsPerPDFPoint
        let deltaX = recordX - x
        let deltaY = recordY - yFromTop
        return deltaX * deltaX + deltaY * deltaY
    }
}

private func integer(in source: String, match: NSTextCheckingResult, group: Int) -> Int? {
    let range = match.range(at: group)
    guard range.location != NSNotFound else { return nil }
    return Int((source as NSString).substring(with: range))
}
