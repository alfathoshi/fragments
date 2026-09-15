//
//  ColorHexSerializer.swift
//  fragments
//
//  Created on 9/16/26.
//

import SwiftUI

extension Color {
    /// Serializes a SwiftUI `Color` into an RGBA component string format ("r,g,b,a").
    public func toRGBAString() -> String {
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        if uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return String(format: "%.4f,%.4f,%.4f,%.4f", red, green, blue, alpha)
        }
        return "0.0000,0.0000,0.0000,1.0000"
    }
    
    /// Reconstructs a SwiftUI `Color` from an RGBA component string format ("r,g,b,a").
    public static func fromRGBAString(_ string: String) -> Color {
        let components = string.split(separator: ",").compactMap { Double($0) }
        guard components.count == 4 else {
            return .blue
        }
        return Color(
            red: components[0],
            green: components[1],
            blue: components[2],
            opacity: components[3]
        )
    }
}
