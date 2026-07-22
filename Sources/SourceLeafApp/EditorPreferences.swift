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

private struct SourceLeafInterfaceScaleKey: EnvironmentKey {
    static let defaultValue = 1.0
}

extension EnvironmentValues {
    var sourceLeafInterfaceScale: Double {
        get { self[SourceLeafInterfaceScaleKey.self] }
        set { self[SourceLeafInterfaceScaleKey.self] = newValue }
    }
}

private struct SourceLeafFontModifier: ViewModifier {
    @Environment(\.sourceLeafInterfaceScale) private var scale
    let style: Font.TextStyle
    let design: Font.Design
    let weight: Font.Weight

    func body(content: Content) -> some View {
        content.font(.system(size: basePointSize * scale, weight: weight, design: design))
    }

    private var basePointSize: Double {
        switch style {
        case .caption2: 10
        case .caption: 11
        case .body: 13
        case .headline: 13
        case .title2: 17
        default: 13
        }
    }
}

extension View {
    func sourceLeafFont(
        _ style: Font.TextStyle,
        design: Font.Design = .default,
        weight: Font.Weight = .regular
    ) -> some View {
        modifier(SourceLeafFontModifier(style: style, design: design, weight: weight))
    }
}
