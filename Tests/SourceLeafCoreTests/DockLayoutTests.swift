import Testing
@testable import SourceLeafCore

@Test func dockLayoutMovesAndRestoresPanels() {
    var layout = DockLayout()
    layout.move(.codex, to: .leading)
    #expect(layout.zones[.leading]?.contains(.codex) == true)
    #expect(layout.zones[.trailing]?.contains(.codex) == false)
    layout.close(.pdf)
    #expect(layout.contains(.pdf) == false)
    layout.show(.pdf)
    #expect(layout.zones[.trailing]?.contains(.pdf) == true)
}

@Test func detachedPanelReturnsToItsPreviousZone() {
    var layout = DockLayout()
    let origin = layout.zone(containing: .pdf)
    #expect(origin == .trailing)
    layout.close(.pdf)
    #expect(!layout.contains(.pdf))
    layout.restore(.pdf, to: origin)
    #expect(layout.zone(containing: .pdf) == .trailing)
    #expect(layout.selected[.trailing] == .pdf)
}
