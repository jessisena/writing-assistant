import AppKit
import SwiftUI

/// The app's colours: blue-black ink, a proofreader's red pencil and a green margin pen on
/// paper and a desk. Each token follows the light or dark appearance of the view it is drawn in.
enum Theme {
    /// App tint: the Polish button, selected chips, the focus edge, links and vocabulary terms.
    static let ink = dynamic(light: 0x33_378A, dark: 0xA9_ADF2)
    /// Background of the writing sheet and the result cards.
    static let paper = dynamic(light: 0xFD_FDFC, dark: 0x1F_2024)
    /// Window background behind the sheet.
    static let desk = dynamic(light: 0xED_EFF3, dark: 0x14_1519)
    /// Hairline dividers and the border of the sheet and the cards.
    static let rule = dynamic(light: 0xD9_DCE3, dark: 0x34_363D)
    /// Removed text in the diff, and the tint behind it at 12%. Also the length meter's warning.
    static let redPencil = dynamic(light: 0xB3_263E, dark: 0xFF_8597)
    /// Added text in the diff, and the tint behind it at 14%.
    static let marginGreen = dynamic(light: 0x1D_7A52, dark: 0x63_D6A3)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        let color = NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        }
        return Color(nsColor: color)
    }
}
