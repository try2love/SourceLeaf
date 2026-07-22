import AppKit
import SwiftUI

enum EditorTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    func isDark(for appearance: NSAppearance) -> Bool {
        switch self {
        case .light: false
        case .dark: true
        case .system: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
    }
}

enum EditorFontCatalog {
    static let systemMonospaced = "__sourceleaf_system_monospaced__"

    static var availableFamilies: [String] {
        NSFontManager.shared.availableFontFamilies.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    static func font(family: String, size: CGFloat) -> NSFont {
        let clampedSize = min(32, max(10, size))
        guard family != systemMonospaced else {
            return .monospacedSystemFont(ofSize: clampedSize, weight: .regular)
        }
        return NSFontManager.shared.font(
            withFamily: family,
            traits: [],
            weight: 5,
            size: clampedSize
        ) ?? NSFont(name: family, size: clampedSize)
            ?? .monospacedSystemFont(ofSize: clampedSize, weight: .regular)
    }
}

enum InterfaceFontScale {
    static func dynamicTypeSize(for scale: Double) -> DynamicTypeSize {
        switch scale {
        case ..<0.90: .small
        case ..<0.98: .medium
        case ..<1.10: .large
        case ..<1.23: .xLarge
        case ..<1.38: .xxLarge
        case ..<1.53: .xxxLarge
        default: .accessibility1
        }
    }
}
