import SwiftUI

/// Adjusts colors for readability against light/dark backgrounds.
/// Brightens dark colors in dark mode, darkens light colors in light mode.
enum ColorContrast {
    static func adjusted(_ color: Color, for colorScheme: ColorScheme) -> Color {
        let resolved = color.resolve(in: .init())
        let r = Double(resolved.red)
        let g = Double(resolved.green)
        let b = Double(resolved.blue)
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b

        if colorScheme == .dark && luminance < 0.3 {
            let boost = 0.4
            return Color(
                red: min(r + boost, 1.0),
                green: min(g + boost, 1.0),
                blue: min(b + boost, 1.0)
            )
        } else if colorScheme == .light && luminance > 0.85 {
            let factor = 0.6
            return Color(red: r * factor, green: g * factor, blue: b * factor)
        }
        return color
    }

    static func adjustedUIColor(_ color: Color, for colorScheme: ColorScheme) -> UIColor {
        UIColor(adjusted(color, for: colorScheme))
    }
}
