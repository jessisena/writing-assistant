import AppKit

extension NSColor {
    /// An sRGB colour from a `0xRRGGBB` value.
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    /// The colour as a `0xRRGGBB` sRGB value, ignoring alpha. Nil when the colour can't be
    /// converted to sRGB, such as a pattern colour.
    var hexValue: UInt32? {
        guard let srgb = usingColorSpace(.sRGB) else { return nil }
        func byte(_ component: CGFloat) -> UInt32 {
            UInt32((min(max(component, 0), 1) * 255).rounded())
        }
        return byte(srgb.redComponent) << 16 | byte(srgb.greenComponent) << 8
            | byte(srgb.blueComponent)
    }
}
