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
