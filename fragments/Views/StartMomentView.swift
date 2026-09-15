//
//  StartMomentView.swift
//  fragments
//
//  Created on 9/13/26.
//

import SwiftUI

public struct StartMomentView: View {
    public var onMomentStarted: ((FolderCollection) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var momentName: String = ""
    @State private var location: String = "Canggu, Bali"
    @State private var selectedTheme: FolderThemeColor = FolderThemeColor.allThemes[0]
    @State private var selectedVibe: String = "Life"
    @State private var date: Date = Date()
    @State private var isCreating: Bool = false

    private let vibeOptions = ["Life", "Travel", "Friends", "Nature", "Creative", "Quiet"]

    public init(onMomentStarted: ((FolderCollection) -> Void)? = nil) {
        self.onMomentStarted = onMomentStarted
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {

                    // Form Fields Section
                    VStack(spacing: 18) {
                        // Moment Title Input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("MOMENT TITLE")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)

                            TextField("e.g. Sunset Walk, Cafe Banter...", text: $momentName)
                                .font(.system(size: 16, weight: .medium))
                                .padding(14)
                                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }


                        // Vibe Tags
                        VStack(alignment: .leading, spacing: 8) {
                            Text("VIBE")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(vibeOptions, id: \.self) { vibe in
                                        Button {
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            selectedVibe = vibe
                                        } label: {
                                            Text(vibe)
                                                .font(.system(size: 13, weight: selectedVibe == vibe ? .bold : .medium, design: .rounded))
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 8)
                                                .background(
                                                    selectedVibe == vibe
                                                        ? AnyShapeStyle(selectedTheme.color ?? Color.blue)
                                                        : AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground)),
                                                    in: Capsule()
                                                )
                                                .foregroundStyle(selectedVibe == vibe ? .white : .primary)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                            }
                        }

                        // Color Palette Theme
                        VStack(alignment: .leading, spacing: 8) {
                            Text("THEME COLOR")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)

                            HStack(spacing: 14) {
                                ForEach(FolderThemeColor.allThemes) { theme in
                                    Button {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        selectedTheme = theme
                                    } label: {
                                        ZStack {
                                            Circle()
                                                .fill(
                                                    LinearGradient(
                                                        colors: theme.swatchGradient,
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                                .frame(width: 38, height: 38)
                                                .shadow(color: (theme.color ?? Color.gray).opacity(0.3), radius: 4, y: 2)

                                            if selectedTheme.id == theme.id {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 14, weight: .bold))
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                        .overlay(
                                            Circle()
                                                .stroke(selectedTheme.id == theme.id ? Color.primary : Color.clear, lineWidth: 2)
                                                .padding(-3)
                                        )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(.horizontal, 20)

                    // Primary Action: Begin Moment
                    Button {
                        handleStartMoment()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                            Text("Begin Moment")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: (selectedTheme.color ?? Color.blue).opacity(0.35), radius: 12, y: 5)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                    .buttonStyle(.glass)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Start a Moment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button() {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
    }

    private func handleStartMoment() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let name = momentName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = name.isEmpty ? "Moment in \(location)" : name

        let newCollection = FolderCollection(
            name: finalTitle,
            location: location,
            date: Date(),
            items: [],
            color: selectedTheme.color
        )

        onMomentStarted?(newCollection)
        dismiss()
    }
}

#if DEBUG
#Preview {
    StartMomentView()
}

struct StartMomentView_Previews: PreviewProvider {
    static var previews: some View {
        StartMomentView()
    }
}
#endif
