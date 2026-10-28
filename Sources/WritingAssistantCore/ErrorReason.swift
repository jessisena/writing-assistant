import Foundation

extension String {
    /// The text without a final period, so a system error description can be followed by ". ".
    var withoutTrailingPeriod: String {
        hasSuffix(".") ? String(dropLast()) : self
    }
}
