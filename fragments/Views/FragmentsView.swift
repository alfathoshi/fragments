//
//  FragmentsView.swift
//  fragments
//
//  Created on 9/13/26.
//

import SwiftUI

public struct FragmentsView: View {
    // MARK: - State
    
    @Binding public var selectedFragment: Fragment?
    @Binding public var incomingNewFragment: Fragment?
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var viewModel: FragmentsViewModel

    public init(
        incomingNewFragment: Binding<Fragment?> = .constant(nil),
        selectedFragment: Binding<Fragment?> = .constant(nil),
        initialFragments: [Fragment] = []
    ) {
        self._incomingNewFragment = incomingNewFragment
        self._selectedFragment = selectedFragment
        self._viewModel = State(initialValue: FragmentsViewModel(initialFragments: initialFragments))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                // Screen Background - Refined Dark/Atmospheric Canvas
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Type Filter Pills (only shown when fragments exist)
                    if !viewModel.fragments.isEmpty {
                        filterBar
                    }
                    
                    // Hero Content: 3D Spatial Sphere or Empty State
                    ZStack {
                        if viewModel.fragments.isEmpty {
                            emptyStateView
                                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        } else {
                            FragmentSphere(
                                fragments: viewModel.displayedFragments,
                                onSelectFragment: { fragment in
                                    withAnimation(.spring(response: 0.38, dampingFraction: 0.76)) {
                                        selectedFragment = fragment
                                    }
                                }
                            )
                            .transition(.opacity)
                        }
                        
                        // Newly Captured Fragment Entrance Animation Overlay
                        if let entering = viewModel.enteringFragment {
                            enteringFragmentOverlay(fragment: entering)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
                // Success Toast Notification
                if let toast = viewModel.toastMessage {
                    VStack {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.tint)
                            Text(toast)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1))
                        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
                        .padding(.top, 50)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        
                        Spacer()
                    }
                    .zIndex(110)
                }
            }
            .navigationTitle("Fragments")
            .toolbarTitleDisplayMode(.inlineLarge)
            .sheet(isPresented: $viewModel.showQuickCaptureSheet) {
                QuickCaptureSheet { newFragment in
                    viewModel.triggerNewFragmentEntrance(newFragment)
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .onAppear {
                viewModel.loadInitialFragments()
            }
            .onChange(of: viewModel.momentManager.standaloneFragments) { _, newFragments in
                viewModel.syncFragments(newFragments)
            }
            .onChange(of: incomingNewFragment) { _, newValue in
                if let frag = newValue {
                    viewModel.handleIncomingFragment(frag)
                    incomingNewFragment = nil
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DeleteFragment"))) { notif in
                if let frag = notif.object as? Fragment {
                    viewModel.handleDelete(fragment: frag)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.78), value: viewModel.fragments.count)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.selectedFilter)
        }
    }
    

    // MARK: - Filter Bar
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "All" Pill
                filterPill(title: "All", count: viewModel.fragments.count, isSelected: viewModel.selectedFilter == nil) {
                    viewModel.selectedFilter = nil
                }

                // Type Pills
                ForEach(FragmentType.allCases) { type in
                    let count = viewModel.fragments.filter { $0.type == type }.count
                    filterPill(
                        title: type.displayName,
                        count: count,
                        icon: type.systemIcon,
                        accentColor: type.accentColor,
                        isSelected: viewModel.selectedFilter == type
                    ) {
                        viewModel.selectedFilter = (viewModel.selectedFilter == type) ? nil : type
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
        }
        .padding(.top, 2)
        .padding(.bottom, 6)
    }

    private func filterPill(
        title: String,
        count: Int,
        icon: String? = nil,
        accentColor: Color = .primary,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let isDark = colorScheme == .dark

        // Dynamic typography & icon styling
        let textColor: Color = isSelected
            ? (isDark ? Color(red: 0.10, green: 0.10, blue: 0.12) : Color.white)
            : (isDark ? Color(white: 0.85) : Color(red: 0.22, green: 0.22, blue: 0.25))

        let iconColor: Color = isSelected
            ? (isDark ? Color(red: 0.10, green: 0.10, blue: 0.12) : Color.white)
            : accentColor

        let countTextColor: Color = isSelected
            ? (isDark ? Color(red: 0.10, green: 0.10, blue: 0.12).opacity(0.85) : Color.white.opacity(0.88))
            : (isDark ? Color(white: 0.60) : Color.secondary)

        let countBgColor: Color = isSelected
            ? (isDark ? Color.black.opacity(0.12) : Color.white.opacity(0.20))
            : (isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))

        // Dynamic capsule surface & border styling
        let pillBgColor: Color = isSelected
            ? (isDark ? Color.white : Color(red: 0.12, green: 0.12, blue: 0.14))
            : (isDark ? Color(red: 0.16, green: 0.16, blue: 0.19) : Color(red: 0.94, green: 0.94, blue: 0.96))

        let borderColor: Color = isSelected
            ? (isDark ? Color.clear : Color.white.opacity(0.15))
            : (isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.06))

        let shadowColor: Color = isSelected
            ? (isDark ? Color.white.opacity(0.18) : Color.black.opacity(0.15))
            : Color.clear

        return Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isSelected ? Color(uiColor: .systemBackground) : .primary)
                }

                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .bold : .medium, design: .rounded))
                    .foregroundStyle(textColor)

                Text("\(count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(countTextColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(countBgColor, in: Capsule())
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 7.5)
            .background(pillBgColor, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(borderColor, lineWidth: 0.8)
            )
            .shadow(color: shadowColor, radius: 4, x: 0, y: 1.5)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Faint Spatial Orbital Guide
            ZStack {
                // Orbital Rings
                Circle()
                    .stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: 1.5, dash: [4, 6]))
                    .frame(width: 200, height: 200)

                Circle()
                    .stroke(Color.primary.opacity(0.06), style: StrokeStyle(lineWidth: 1, dash: [3, 8]))
                    .frame(width: 260, height: 260)

                // Center Icon
                VStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(Color.primary)
                }
            }

            // Center Copy
            VStack(spacing: 8) {
                Text("Nothing here yet")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Quick captures your tiny moments")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
    }

    // MARK: - New Fragment Entering Animation Overlay
    @ViewBuilder
    private func enteringFragmentOverlay(fragment: Fragment) -> some View {
        ZStack {
            // Ambient light pulse
            Circle()
                .fill(fragment.gradientColors.first?.opacity(0.25) ?? Color.blue.opacity(0.2))
                .frame(width: 200, height: 200)
                .blur(radius: 40)
                .scaleEffect(viewModel.enteringStep == 0 ? 1.3 : 0.6)
                .opacity(viewModel.enteringStep < 2 ? 1.0 : 0.0)

            FragmentNode(fragment: fragment, normalizedZ: 1.0)
                .scaleEffect(viewModel.enteringStep == 0 ? 1.35 : (viewModel.enteringStep == 1 ? 0.95 : 1.0))
                .offset(
                    x: viewModel.enteringStep == 0 ? 0 : 30,
                    y: viewModel.enteringStep == 0 ? -20 : 10
                )
                .shadow(
                    color: fragment.gradientColors.first?.opacity(0.5) ?? Color.blue.opacity(0.4),
                    radius: viewModel.enteringStep == 0 ? 25 : 8,
                    y: 10
                )
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}

#if DEBUG
#Preview("FragmentsView - With Items (Light)") {
    FragmentsView(initialFragments: Fragment.sampleFragments)
}

#Preview("FragmentsView - With Items (Dark)") {
    FragmentsView(initialFragments: Fragment.sampleFragments)
        .preferredColorScheme(.dark)
}

#Preview("FragmentsView - Empty State (Light)") {
    FragmentsView()
}

#Preview("FragmentsView - Empty State (Dark)") {
    FragmentsView()
        .preferredColorScheme(.dark)
}
#endif
