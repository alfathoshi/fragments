//
//  EndMomentSheet.swift
//  fragments
//
//  Created on 9/15/26.
//

import SwiftUI

public struct EndMomentSheet: View {
    public let session: MomentSession
    public var onSave: (String, String, Color?, String) -> Void
    public var onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var momentName: String = ""
    @State private var selectedCategory: String = "Life"
    @State private var selectedTheme: FolderThemeColor = FolderThemeColor.allThemes[0]
    @State private var location: String
    @State private var showDiscardConfirmation: Bool = false

    private let categoryOptions = [
        "Life", "Travel", "Friends", "Nature", "Creative", "Quiet", "Work"
    ]

    public init(
        session: MomentSession,
        onSave: @escaping (String, String, Color?, String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.session = session
        self.onSave = onSave
        self.onCancel = onCancel
        self._location = State(initialValue: session.location)
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {

                    // 1. Session Hero Summary Card with Animated ThinkingOrb
                    sessionHeroCard
                        .padding(.top, 8)

                    // 2. Form Inputs Section
                    VStack(spacing: 20) {

                        // Moment Title Input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("MOMENT NAME")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)

                            TextField(defaultPlaceholder, text: $momentName)
                                .font(.system(size: 16, weight: .medium))
                                .padding(14)
                                .background(
                                    Color(uiColor: .secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                                )
                        }
                        .padding(.horizontal, 20)

                        // Category / Vibe Pills
                        VStack(alignment: .leading, spacing: 8) {
                            Text("CATEGORY")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 20)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(categoryOptions, id: \.self) { cat in
                                        Button {
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            selectedCategory = cat
                                        } label: {
                                            Text(cat)
                                                .font(.system(size: 13, weight: selectedCategory == cat ? .bold : .medium, design: .rounded))
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 8)
                                                .background(
                                                    selectedCategory == cat
                                                        ? AnyShapeStyle(selectedTheme.color ?? Color.primary)
                                                        : AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground)),
                                                    in: Capsule()
                                                )
                                                .foregroundStyle(
                                                    selectedCategory == cat
                                                        ?  Color.white
                                                        : Color.primary
                                                )
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }

                        // Theme Color Palette
                        VStack(alignment: .leading, spacing: 8) {
                            Text("FOLDER COLOR")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)

                            HStack(spacing: 24) {
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

                }
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Complete Moment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Discard", role: .destructive) {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        showDiscardConfirmation = true
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.red)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        handleSave()
                    }
                    .font(.body.weight(.semibold))
                    .buttonStyle(.glassProminent)
                    .tint(.primary)
                    
                }
            }
            .alert(
                "Discard Moment?",
                isPresented: $showDiscardConfirmation
            ) {
                Button("Cancel", role: .cancel) { }
                Button("Discard", role: .destructive) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onCancel()
                    dismiss()
                }
            } message: {
                Text("Are you sure you want to discard this moment? Any captured fragments will not be saved.")
            }
        }
    }

    // MARK: - Hero Summary Card
    private var sessionHeroCard: some View {
        HStack(spacing: 18) {
            ThinkingOrb(state: .connecting, size: 56, tint: selectedTheme.color)

            VStack(alignment: .leading, spacing: 4) {
                Text("Moment Completed")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(session.fragmentCountText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text("•")
                        .foregroundStyle(.secondary)

                    Image(systemName: "clock")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(session.formattedElapsed())
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(16)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }

    private var defaultPlaceholder: String {
        let hour = Calendar.current.component(.hour, from: session.startDate)
        let timePeriod: String
        switch hour {
        case 5..<12: timePeriod = "Morning"
        case 12..<17: timePeriod = "Afternoon"
        case 17..<21: timePeriod = "Evening"
        default: timePeriod = "Night"
        }
        return "\(timePeriod) \(selectedCategory)"
    }

    private func handleSave() {
        let name = momentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? defaultPlaceholder
            : momentName.trimmingCharacters(in: .whitespacesAndNewlines)

        onSave(name, selectedCategory, selectedTheme.color, location)
        dismiss()
    }
}

#if DEBUG
#Preview {
    EndMomentSheet(
        session: MomentSession(
            startDate: Date().addingTimeInterval(-300),
            fragments: [
                Fragment(type: .photo, title: "Coffee Art", subtitle: "02:15 PM"),
                Fragment(type: .note, title: "Idea snippet", subtitle: "02:18 PM")
            ],
            location: "Jakarta, ID"
        ),
        onSave: { _, _, _, _ in },
        onCancel: {}
    )
}
#endif
