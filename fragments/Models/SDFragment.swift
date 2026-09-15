//
//  SDFragment.swift
//  fragments
//
//  Created on 9/16/26.
//

import Foundation
import SwiftData
import SwiftUI

@Model
public final class SDFragment {
    @Attribute(.unique) public var id: UUID
    public var typeRawValue: String
    public var createdAt: Date
    public var title: String
    public var subtitle: String?
    public var text: String?
    public var mediaSymbol: String?
    public var mediaResourceName: String?
    public var gradientRGBAStrings: [String]
    public var location: String?
    public var duration: String?
    public var audioWaveform: [Double]
    
    public var phi: Double
    public var theta: Double
    public var radiusFactor: Double
    public var baseWidth: Double
    public var baseHeight: Double

    public init(
        id: UUID = UUID(),
        typeRawValue: String,
        createdAt: Date = Date(),
        title: String,
        subtitle: String? = nil,
        text: String? = nil,
        mediaSymbol: String? = nil,
        mediaResourceName: String? = nil,
        gradientRGBAStrings: [String] = [],
        location: String? = nil,
        duration: String? = nil,
        audioWaveform: [Double] = [],
        phi: Double = 0.0,
        theta: Double = 0.0,
        radiusFactor: Double = 1.0,
        baseWidth: Double = 90,
        baseHeight: Double = 105
    ) {
        self.id = id
        self.typeRawValue = typeRawValue
        self.createdAt = createdAt
        self.title = title
        self.subtitle = subtitle
        self.text = text
        self.mediaSymbol = mediaSymbol
        self.mediaResourceName = mediaResourceName
        self.gradientRGBAStrings = gradientRGBAStrings
        self.location = location
        self.duration = duration
        self.audioWaveform = audioWaveform
        self.phi = phi
        self.theta = theta
        self.radiusFactor = radiusFactor
        self.baseWidth = baseWidth
        self.baseHeight = baseHeight
    }

    public convenience init(from fragment: Fragment) {
        self.init(
            id: fragment.id,
            typeRawValue: fragment.type.rawValue,
            createdAt: fragment.createdAt,
            title: fragment.title,
            subtitle: fragment.subtitle,
            text: fragment.text,
            mediaSymbol: fragment.mediaSymbol,
            mediaResourceName: fragment.mediaResourceName,
            gradientRGBAStrings: fragment.gradientColors.map { $0.toRGBAString() },
            location: fragment.location,
            duration: fragment.duration,
            audioWaveform: fragment.audioWaveform.map { Double($0) },
            phi: fragment.phi,
            theta: fragment.theta,
            radiusFactor: fragment.radiusFactor,
            baseWidth: Double(fragment.baseSize.width),
            baseHeight: Double(fragment.baseSize.height)
        )
    }

    public func toFragment() -> Fragment {
        let type = FragmentType(rawValue: typeRawValue) ?? .note
        let colors = gradientRGBAStrings.map { Color.fromRGBAString($0) }
        let waveforms = audioWaveform.map { CGFloat($0) }
        
        return Fragment(
            id: id,
            type: type,
            createdAt: createdAt,
            title: title,
            subtitle: subtitle,
            text: text,
            mediaSymbol: mediaSymbol,
            mediaResourceName: mediaResourceName,
            gradientColors: colors.isEmpty ? [Color.blue, Color.purple] : colors,
            location: location,
            duration: duration,
            audioWaveform: waveforms,
            phi: phi,
            theta: theta,
            radiusFactor: radiusFactor,
            baseSize: CGSize(width: baseWidth, height: baseHeight)
        )
    }
}
