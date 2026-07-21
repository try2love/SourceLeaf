import Foundation

public struct DocumentOutlineItem: Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var level: Int
    public var title: String
    public var line: Int

    public init(level: Int, title: String, line: Int) {
        self.level = level
        self.title = title
        self.line = line
    }
}

public struct ProjectIndex: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var rootDocument: String?
    public var sectionSummaries: [String: [String]]
    public var labels: [String: String]
    public var citations: [String]
    public var includedFiles: [String]

    public init(
        generatedAt: Date = Date(),
        rootDocument: String?,
        sectionSummaries: [String: [String]],
        labels: [String: String],
        citations: [String],
        includedFiles: [String]
    ) {
        self.generatedAt = generatedAt
        self.rootDocument = rootDocument
        self.sectionSummaries = sectionSummaries
        self.labels = labels
        self.citations = citations
        self.includedFiles = includedFiles
    }
}

public enum ProjectIndexer {
    private static let acceptedExtensions: Set<String> = [
        "tex", "bib", "sty", "cls", "bst", "png", "jpg", "jpeg", "pdf", "eps", "svg"
    ]

    public static func discoverFiles(root: URL, fileManager: FileManager = .default) -> [ProjectFile] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        let excludedDirectories: Set<String> = [".git", ".build", "build", "DerivedData", "临时文件"]
        var files: [ProjectFile] = []

        for case let url as URL in enumerator {
            if excludedDirectories.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            let ext = url.pathExtension.lowercased()
            guard acceptedExtensions.contains(ext) else { continue }
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let relative = String(url.path.dropFirst(root.path.hasSuffix("/") ? root.path.count : root.path.count + 1))
            files.append(ProjectFile(relativePath: relative, url: url, kind: kind(for: ext)))
        }

        return files.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    public static func detectRootDocument(files: [ProjectFile]) -> ProjectFile? {
        let texFiles = files.filter { $0.kind == .tex }
        let candidates = texFiles.compactMap { file -> (ProjectFile, Int)? in
            guard let text = try? String(contentsOf: file.url, encoding: .utf8),
                  text.range(of: #"\\documentclass(?:\[[^\]]*\])?\s*\{"#, options: .regularExpression) != nil else {
                return nil
            }
            var score = 10
            if text.contains("\\begin{document}") { score += 5 }
            if file.url.lastPathComponent.lowercased().contains("main") { score += 3 }
            if !file.relativePath.contains("/") { score += 1 }
            return (file, score)
        }
        return candidates.max { $0.1 < $1.1 }?.0
    }

    public static func tree(files: [ProjectFile]) -> [ProjectTreeNode] {
        let root = ProjectTreeBuilder(name: "", relativePath: "")
        for file in files {
            let components = file.relativePath.split(separator: "/").map(String.init)
            guard !components.isEmpty else { continue }
            var current = root
            var pathComponents: [String] = []
            for component in components.dropLast() {
                pathComponents.append(component)
                let path = pathComponents.joined(separator: "/")
                if let existing = current.directories[component] {
                    current = existing
                } else {
                    let directory = ProjectTreeBuilder(name: component, relativePath: path)
                    current.directories[component] = directory
                    current = directory
                }
            }
            current.files.append(file)
        }
        return root.nodes()
    }

    public static func outline(for source: String) -> [DocumentOutlineItem] {
        let pattern = #"\\(part|chapter|section|subsection|subsubsection|paragraph)\*?\s*\{([^}]*)\}"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsSource = source as NSString
        return expression.matches(in: source, range: NSRange(location: 0, length: nsSource.length)).compactMap { match in
            guard match.numberOfRanges == 3 else { return nil }
            let command = nsSource.substring(with: match.range(at: 1))
            let title = nsSource.substring(with: match.range(at: 2))
            let prefix = nsSource.substring(to: match.range.location)
            let line = prefix.reduce(into: 1) { count, character in
                if character == "\n" { count += 1 }
            }
            let levels = ["part": 0, "chapter": 1, "section": 2, "subsection": 3, "subsubsection": 4, "paragraph": 5]
            return DocumentOutlineItem(level: levels[command] ?? 2, title: title, line: line)
        }
    }

    public static func sectionContext(source: String, containingLine line: Int) -> String {
        let outlines = outline(for: source)
        guard let current = outlines.last(where: { $0.line <= line }) else { return source }
        let endLine = outlines.first(where: { $0.line > current.line && $0.level <= current.level })?.line ?? Int.max
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        let startIndex = max(0, current.line - 1)
        let endIndex = min(lines.count, endLine == Int.max ? lines.count : endLine - 1)
        return lines[startIndex..<endIndex].joined(separator: "\n")
    }

    public static func nearbyContext(source: String, target: SourceTarget, radius: Int = 30) -> String {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        let start = max(0, target.startLine - radius - 1)
        let end = min(lines.count, target.endLine + radius)
        return lines[start..<end].joined(separator: "\n")
    }

    private static func kind(for ext: String) -> ProjectFile.Kind {
        switch ext {
        case "tex": .tex
        case "bib", "bst": .bibliography
        case "sty", "cls": .style
        case "png", "jpg", "jpeg", "pdf", "eps", "svg": .image
        default: .other
        }
    }
}

private final class ProjectTreeBuilder {
    let name: String
    let relativePath: String
    var directories: [String: ProjectTreeBuilder] = [:]
    var files: [ProjectFile] = []

    init(name: String, relativePath: String) {
        self.name = name
        self.relativePath = relativePath
    }

    func nodes() -> [ProjectTreeNode] {
        let directoryNodes = directories.values
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { directory in
                ProjectTreeNode(
                    id: "directory:\(directory.relativePath)",
                    name: directory.name,
                    relativePath: directory.relativePath,
                    children: directory.nodes()
                )
            }
        let fileNodes = files
            .sorted { $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }
            .map { file in
                ProjectTreeNode(
                    id: "file:\(file.relativePath)",
                    name: file.url.lastPathComponent,
                    relativePath: file.relativePath,
                    file: file
                )
            }
        return directoryNodes + fileNodes
    }
}
