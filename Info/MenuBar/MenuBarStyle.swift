import CoreGraphics

/// How each metric labels itself in the menu bar.
enum MenuBarLabelStyle: String, CaseIterable, Sendable {
    case icon, text, none

    var title: String {
        switch self {
        case .icon: "Icon"
        case .text: "Text"
        case .none: "None"
        }
    }
}

/// Menu bar value text size.
enum MenuBarTextSize: String, CaseIterable, Sendable {
    case small, medium, large

    var points: CGFloat {
        switch self {
        case .small: 10
        case .medium: 11.5
        case .large: 13.5
        }
    }

    var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }
}

/// Internal spacing/density for each status item. macOS controls the outer gap
/// between separate status items, but tightening the item's internal padding
/// makes Info sit much closer to native menu extras.
enum MenuBarSpacing: String, CaseIterable, Sendable {
    case compact, regular, spacious

    var title: String {
        switch self {
        case .compact: "Compact"
        case .regular: "Regular"
        case .spacious: "Spacious"
        }
    }

    var leadingPad: CGFloat {
        switch self {
        case .compact: 0
        case .regular: 3
        case .spacious: 5
        }
    }

    var trailingPad: CGFloat { leadingPad }

    var labelGap: CGFloat {
        switch self {
        case .compact: 1
        case .regular: 3
        case .spacious: 5
        }
    }

    var sparkGap: CGFloat {
        switch self {
        case .compact: 2
        case .regular: 4
        case .spacious: 6
        }
    }

    func sparkWidth(for kind: MetricKind) -> CGFloat {
        switch (self, kind.isMirrored) {
        case (.compact, false): 16
        case (.compact, true): 20
        case (.regular, false): 26
        case (.regular, true): 32
        case (.spacious, false): 34
        case (.spacious, true): 42
        }
    }
}

/// How the label and value are arranged relative to each other.
enum MenuBarLayout: String, CaseIterable, Sendable {
    /// Value right-aligned in a stable, reserved column. Keeps a fixed width
    /// (no per-tick jiggle) but leaves a gap between a short value and the label.
    case inline
    /// Value left-aligned so it hugs the label, removing the leading gap. The
    /// reserved column is preserved for width stability, so the slack moves to
    /// the trailing edge instead of sitting between the label and the value.
    case tight
    /// Label stacked on top of the value, drawn with smaller type so both lines
    /// fit within the menu bar's height.
    case stacked

    var title: String {
        switch self {
        case .inline: "Inline"
        case .tight: "Tight"
        case .stacked: "Stacked"
        }
    }
}

/// The full set of menu-bar appearance options.
struct MenuBarStyle: Sendable, Equatable {
    var showSparkline: Bool = false
    var showValue: Bool = true
    var label: MenuBarLabelStyle = .text
    var textSize: MenuBarTextSize = .medium
    var spacing: MenuBarSpacing = .compact
    var layout: MenuBarLayout = .inline
}
