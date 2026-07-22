import Foundation
import Testing
@testable import SourceLeafApp

@MainActor
@Test func customizedPromptPersistsAcrossApplicationModels() throws {
    let state = try productTestState(named: "prompts")
    defer { state.cleanup() }
    let first = AppModel(restoreLastProject: false, supportDirectory: state.support, defaults: state.defaults)
    let prompt = first.addPrompt()
    let index = try #require(first.promptTemplates.firstIndex { $0.id == prompt.id })
    first.promptTemplates[index].nameZH = "压缩论文摘要"
    first.promptTemplates[index].bodyZH = "保留事实与引用，只压缩冗余表达。"
    first.promptTemplates[index].enabled = false
    first.savePromptTemplates()

    let restored = AppModel(restoreLastProject: false, supportDirectory: state.support, defaults: state.defaults)
    let saved = try #require(restored.promptTemplates.first { $0.id == prompt.id })
    #expect(saved.nameZH == "压缩论文摘要")
    #expect(saved.bodyZH == "保留事实与引用，只压缩冗余表达。")
    #expect(!saved.enabled)
    #expect(!saved.builtIn)
}

@MainActor
@Test func applicationRestoresTheLastProjectAndSourceFile() throws {
    guard let fixturesPath = ProcessInfo.processInfo.environment["SOURCELEAF_BOUNDARY_PROJECTS"] else { return }
    let state = try productTestState(named: "restore")
    defer { state.cleanup() }
    let project = URL(fileURLWithPath: fixturesPath, isDirectory: true)
        .appendingPathComponent("多文件论文", isDirectory: true)
    let first = AppModel(restoreLastProject: false, supportDirectory: state.support, defaults: state.defaults)
    first.openProject(project)
    let details = try #require(first.projectFiles.first { $0.relativePath == "sections/deep/details.tex" })
    first.openFile(details)

    let restored = AppModel(restoreLastProject: true, supportDirectory: state.support, defaults: state.defaults)
    #expect(restored.projectRoot?.standardizedFileURL == project.standardizedFileURL)
    #expect(restored.selectedFile?.relativePath == "sections/deep/details.tex")
}

@MainActor
@Test func detachedPanelReturnsToTheMainWorkspaceWhenItsWindowCloses() throws {
    let state = try productTestState(named: "floating")
    defer { state.cleanup() }
    let model = AppModel(restoreLastProject: false, supportDirectory: state.support, defaults: state.defaults)
    let originalZone = model.layout.zone(containing: .pdf)
    model.detachPanel(.pdf)
    #expect(model.floatingPanels.contains(.pdf))
    #expect(!model.layout.contains(.pdf))

    model.restoreFloatingPanel(.pdf)
    #expect(!model.floatingPanels.contains(.pdf))
    #expect(model.layout.zone(containing: .pdf) == originalZone)
}

private struct ProductTestState {
    var support: URL
    var defaults: UserDefaults
    var suiteName: String

    func cleanup() {
        try? FileManager.default.removeItem(at: support)
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private func productTestState(named name: String) throws -> ProductTestState {
    let base: URL
    if let configured = ProcessInfo.processInfo.environment["SOURCELEAF_TEST_ARTIFACT_ROOT"] {
        base = URL(fileURLWithPath: configured, isDirectory: true)
    } else {
        base = FileManager.default.temporaryDirectory
    }
    let support = base.appendingPathComponent("产品状态-\(name)-\(UUID().uuidString)", isDirectory: true)
    let suiteName = "SourceLeaf.product.\(name).\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    return ProductTestState(support: support, defaults: defaults, suiteName: suiteName)
}
