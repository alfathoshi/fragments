//
//  QuickCaptureSheet.swift
//  fragments
//
//  Created on 9/13/26.
//

import SwiftUI

public struct QuickCaptureSheet: View {
    public var onCapture: (Fragment) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: FragmentType
    @State private var title: String = ""
    @State private var textContent: String = ""
    @State private var location: String = ""

    public init(initialType: FragmentType = .photo, onCapture: @escaping (Fragment) -> Void) {
        self._selectedType = State(initialValue: initialType)
        self.onCapture = onCapture
    }

    public var body: some View {
        NavigationStack {
            Form {
                // Type Selector Segmented
                Section {
                    Picker("Fragment Type", selection: $selectedType) {
                        ForEach(FragmentType.allCases) { type in
                            Label(type.displayName, systemImage: type.systemIcon)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
                } header: {
                    Text("Capture Type")
                }

                // Title & Content
                Section {
                    TextField(titlePlaceholder, text: $title)
                        .font(.body)

                    if selectedType == .note || selectedType == .audio {
                        TextField(
                            selectedType == .note ? "Note thoughts, snippet, or quote..." : "Voice transcription or note...",
                            text: $textContent,
                            axis: .vertical
                        )
                        .lineLimit(3...6)
                    }

                    TextField("Location (optional)", text: $location)
                } header: {
                    Text("Details")
                } footer: {
                    Text("Quick captures float freely in your Fragments sphere until you add them to an intentional Moment.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Visual Preview Card
                Section("Sphere Appearance Preview") {
                    HStack {
                        Spacer()
                        FragmentNode(
                            fragment: previewFragment,
                            normalizedZ: 1.0
                        )
                        .frame(width: previewFragment.baseSize.width, height: previewFragment.baseSize.height)
                        .padding(.vertical, 8)
                        Spacer()
                    }
                }
            }
            .navigationTitle("Quick Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Float into Sphere") {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        let newFragment = previewFragment
                        dismiss()
                        onCapture(newFragment)
                    }
                    .font(.body.weight(.semibold))
                }
            }
        }
    }

    private var titlePlaceholder: String {
        switch selectedType {
        case .photo: return "Photo caption (e.g. Sunset reflections)"
        case .video: return "Video title (e.g. Friends around the fire)"
        case .audio: return "Audio title (e.g. Birds at dawn)"
        case .note:  return "Note heading (e.g. Idea for a story)"
        }
    }

    private var previewFragment: Fragment {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = trimmedTitle.isEmpty ? defaultTitle : trimmedTitle
        let randomPhi = Double.random(in: -0.55...0.55)
        let randomTheta = Double.random(in: 0.0...(2.0 * .pi))

        switch selectedType {
        case .photo:
            return Fragment(
                type: .photo,
                createdAt: Date(),
                title: displayTitle,
                subtitle: location.isEmpty ? "Quick snapshot" : location,
                mediaSymbol: "camera.viewfinder",
                gradientColors: [Color(red: 1.0, green: 0.55, blue: 0.40), Color(red: 0.90, green: 0.20, blue: 0.50)],
                location: location.isEmpty ? nil : location,
                phi: randomPhi,
                theta: randomTheta,
                radiusFactor: 1.02,
                baseSize: CGSize(width: 104, height: 122)
            )
        case .video:
            return Fragment(
                type: .video,
                createdAt: Date(),
                title: displayTitle,
                subtitle: location.isEmpty ? "0:12 clip" : location,
                mediaSymbol: "video.fill",
                gradientColors: [Color(red: 0.25, green: 0.55, blue: 0.95), Color(red: 0.15, green: 0.85, blue: 0.80)],
                location: location.isEmpty ? nil : location,
                duration: "0:12",
                phi: randomPhi,
                theta: randomTheta,
                radiusFactor: 0.98,
                baseSize: CGSize(width: 100, height: 116)
            )
        case .audio:
            return Fragment(
                type: .audio,
                createdAt: Date(),
                title: displayTitle,
                subtitle: "Voice snippet",
                text: textContent.isEmpty ? "“Unspoken thoughts captured in the moment.”" : textContent,
                mediaSymbol: "mic.fill",
                gradientColors: [Color(red: 0.20, green: 0.75, blue: 0.58), Color(red: 0.12, green: 0.45, blue: 0.40)],
                location: location.isEmpty ? nil : location,
                duration: "0:09",
                audioWaveform: [0.3, 0.6, 0.9, 0.4, 0.8, 1.0, 0.7, 0.5, 0.85, 0.6, 0.4, 0.7, 0.9, 0.3],
                phi: randomPhi,
                theta: randomTheta,
                radiusFactor: 1.03,
                baseSize: CGSize(width: 116, height: 88)
            )
        case .note:
            return Fragment(
                type: .note,
                createdAt: Date(),
                title: displayTitle,
                subtitle: "Raw thought",
                text: textContent.isEmpty ? "A fleeting glimpse of wonder that caught my attention." : textContent,
                mediaSymbol: "text.quote",
                gradientColors: [Color(red: 0.82, green: 0.58, blue: 0.38), Color(red: 0.58, green: 0.35, blue: 0.22)],
                location: location.isEmpty ? nil : location,
                phi: randomPhi,
                theta: randomTheta,
                radiusFactor: 0.97,
                baseSize: CGSize(width: 114, height: 98)
            )
        }
    }

    private var defaultTitle: String {
        switch selectedType {
        case .photo: return "Golden horizon"
        case .video: return "Campfire sparks"
        case .audio: return "Evening murmur"
        case .note:  return "Fleeting spark"
        }
    }
}
