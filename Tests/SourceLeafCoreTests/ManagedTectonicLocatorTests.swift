import Foundation
import Testing
@testable import SourceLeafCore

@Suite("Managed Tectonic locator")
struct ManagedTectonicLocatorTests {
    @Test("uses the matching executable bundled architecture")
    func usesBundledArchitecture() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SourceLeaf-managed-engine-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("Engines/arm64/tectonic")
        try FileManager.default.createDirectory(
            at: executable.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("test".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let resolved = ManagedTectonicLocator.resolve(
            bundleResourceURL: root,
            supportDirectory: nil,
            architecture: "arm64"
        )

        #expect(resolved == executable)
    }

    @Test("falls back to the legacy Application Support engine")
    func fallsBackToSupportDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SourceLeaf-managed-engine-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("Engines/tectonic")
        try FileManager.default.createDirectory(
            at: executable.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("test".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let resolved = ManagedTectonicLocator.resolve(
            bundleResourceURL: nil,
            supportDirectory: root,
            architecture: "arm64"
        )

        #expect(resolved == executable)
    }
}
