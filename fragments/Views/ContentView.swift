//
//  ContentView.swift
//  fragments
//
//  Created by Muhammad Bintang Al-Fath on 9/12/26.
//

import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case capture
    case fragments
    case logs
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var momentManager = MomentManager.shared

    @State private var selectedTab: AppTab = .fragments
    @State private var activeTab: AppTab = .fragments // The actual tab displayed underneath blur
    @State private var incomingNewFragment: Fragment? = nil

    // Floating Capture Menu & Modals
    @State private var isCaptureMenuOpen: Bool = false
    @State private var showActiveMomentView: Bool = false
    @State private var showQuickCaptureSheet: Bool = false
    @State private var showDiscardConfirmation: Bool = false
    @State private var showResumeOrNewMomentAlert: Bool = false
    @State private var showDiscardForQuickCaptureAlert: Bool = false
    @State private var selectedFragment: Fragment? = nil
    @State private var quickCaptureInitialType: FragmentType = .photo
    @State private var pendingQuickCaptureType: FragmentType = .photo
    @State private var activeMomentInitialCaptureType: FragmentType? = nil
    @State private var activeMomentAutoOpenEnd: Bool = false

    private var currentTab: AppTab {
        selectedTab == .capture ? activeTab : selectedTab
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Native TabView (Blurred when Capture Menu or Fragment Detail is Open)
            TabView(selection: $selectedTab) {
                if #available(iOS 27.0, *) {
                    Tab("Capture", systemImage: "plus", value: AppTab.capture, role: .prominent) {
                        Color.clear
                    }
                } else {
                    Tab("Capture", systemImage: "plus", value: AppTab.capture, role: .search) {
                        Color.clear
                    }
                }

                Tab(value: AppTab.fragments) {
                    FragmentsView(
                        incomingNewFragment: $incomingNewFragment,
                        selectedFragment: $selectedFragment
                    )
                } label: {
                    Label {
                        Text("Fragments")
                    } icon: {
                        Image(systemName: currentTab == .fragments ? "circle.hexagongrid.fill" : "circle.hexagongrid")
                            .environment(\.symbolVariants, .none)
                    }
                    .environment(\.symbolVariants, .none)
                    .id("tab_fragments_\(currentTab == .fragments)")
                }

                Tab(value: AppTab.logs) {
                    MomentsView(momentManager: momentManager)
                } label: {
                    Label {
                        Text("Moments")
                    } icon: {
                        Image(systemName: currentTab == .logs ? "rectangle.stack.fill" : "rectangle.stack")
                            .environment(\.symbolVariants, .none)
                    }
                    .environment(\.symbolVariants, .none)
                    .id("tab_moments_\(currentTab == .logs)")
                }
            }
            .tint(.primary)
            .blur(radius: (isCaptureMenuOpen || selectedFragment != nil) ? 1 : 0)
            .animation(.easeInOut(duration: 0.28), value: isCaptureMenuOpen || selectedFragment != nil)

            // Floating Active Session Orb Widget (When moment is active and ActiveMomentView is minimized - at bottom above tab bar)
            if momentManager.isSessionActive && !showActiveMomentView && selectedTab != .capture && selectedFragment == nil {
                activeSessionFloatingIsland
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 64)
                    .zIndex(40)
            }

            // Floating 3D Orbs Capture Overlay
            if isCaptureMenuOpen {
                FloatingCaptureOverlay(
                    isOpen: $isCaptureMenuOpen,
                    onSelectStartMoment: {
                        if momentManager.isSessionActive {
                            showResumeOrNewMomentAlert = true
                        } else {
                            momentManager.startSession()
                            showActiveMomentView = true
                        }
                    },
                    onSelectQuickCaptureType: { type in
                        if momentManager.isSessionActive {
                            pendingQuickCaptureType = type
                            showDiscardForQuickCaptureAlert = true
                        } else {
                            quickCaptureInitialType = type
                            showQuickCaptureSheet = true
                        }
                    }
                )
                .transition(.opacity)
                .zIndex(50)
            }

            // Fragment Detail Focused Preview Modal (Overlays TabBar, Navigation bar, and entire window)
            if let fragment = selectedFragment {
                FragmentDetailView(
                    fragment: fragment,
                    onDelete: { frag in
                        NotificationCenter.default.post(name: NSNotification.Name("DeleteFragment"), object: frag)
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                            selectedFragment = nil
                        }
                    },
                    onDismiss: {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                            selectedFragment = nil
                        }
                    }
                )
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: momentManager.activeSession != nil)
        .onChange(of: selectedTab) { oldTab, newTab in
            if newTab == .capture {
                // Intercept capture tab tap: pop up the floating orbs and blur the screen!
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.spring(response: 0.36, dampingFraction: 0.74)) {
                    isCaptureMenuOpen = true
                }
                // Keep the underlying view on the previous tab so it blurs gorgeously
                selectedTab = (oldTab == .capture) ? .fragments : oldTab
            } else {
                activeTab = newTab
            }
        }
        // Active Moment View (Full Spatial Screen with Bottom Floating ThinkingOrb)
        .fullScreenCover(isPresented: $showActiveMomentView) {
            ActiveMomentView(
                momentManager: momentManager,
                initialCaptureType: activeMomentInitialCaptureType,
                autoOpenEnd: activeMomentAutoOpenEnd,
                onDismiss: {
                    showActiveMomentView = false
                    activeMomentInitialCaptureType = nil
                    activeMomentAutoOpenEnd = false
                },
                onSaveComplete: {
                    showActiveMomentView = false
                    activeMomentInitialCaptureType = nil
                    activeMomentAutoOpenEnd = false
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                        selectedTab = .logs
                        activeTab = .logs
                    }
                }
            )
        }
        // Quick Capture Sheet (For standalone quick captures outside active moment)
        .fullScreenCover(isPresented: $showQuickCaptureSheet) {
            CaptureView(
                initialMode: {
                    switch quickCaptureInitialType {
                    case .photo: return .photo
                    case .video: return .video
                    case .note: return .note
                    case .audio: return .memo
                    }
                }(),
                activeSession: momentManager.activeSession,
                onCaptureFragment: { newFragment in
                    handleFragmentCaptured(newFragment)
                    showQuickCaptureSheet = false
                },
                onClose: {
                    showQuickCaptureSheet = false
                },
                onEndActiveMoment: {
                    showQuickCaptureSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        momentManager.requestEndSession()
                    }
                }
            )
        }
        // End Moment Sheet fallback
        .sheet(isPresented: $momentManager.showEndMomentSheet) {
            if let session = momentManager.activeSession {
                EndMomentSheet(
                    session: session,
                    onSave: { name, category, color, location in
                        momentManager.finishSession(
                            name: name,
                            category: category,
                            color: color,
                            location: location
                        )
                        showActiveMomentView = false
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            selectedTab = .logs
                            activeTab = .logs
                        }
                    },
                    onCancel: {
                        momentManager.cancelSession()
                        showActiveMomentView = false
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
            }
        }
        .alert(
            "Discard Moment?",
            isPresented: $showDiscardConfirmation
        ) {
            Button("Cancel", role: .cancel) { }
            Button("Discard", role: .destructive) {
                momentManager.cancelSession()
            }
        } message: {
            Text("Are you sure you want to discard this moment? Any captured fragments will not be saved.")
        }
        // Confirmation when starting a moment while one is already active
        .alert(
            "Moment in Progress",
            isPresented: $showResumeOrNewMomentAlert
        ) {
            Button("Resume Moment") {
                showActiveMomentView = true
            }
            Button("Start New Moment", role: .destructive) {
                momentManager.cancelSession()
                momentManager.startSession()
                showActiveMomentView = true
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You already have an active moment. Would you like to resume it, or discard it and start a new moment?")
        }
        // Confirmation when starting quick capture while moment is active
        .alert(
            "Discard Active Moment?",
            isPresented: $showDiscardForQuickCaptureAlert
        ) {
            Button("Cancel", role: .cancel) { }
            Button("Discard", role: .destructive) {
                momentManager.cancelSession()
                quickCaptureInitialType = pendingQuickCaptureType
                showQuickCaptureSheet = true
            }
        } message: {
            Text("Starting a quick capture will discard your currently active moment. Any captured fragments will not be saved.")
        }
        .onAppear {
            momentManager.setModelContext(modelContext)
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "fragments" else { return }

        // Close any standalone detail views or menus that might block presentation
        selectedFragment = nil
        isCaptureMenuOpen = false

        if url.host == "end" {
            // Dismiss any existing active moment cover first so we can cleanly open end sheet
            showActiveMomentView = false
            activeMomentInitialCaptureType = nil
            activeMomentAutoOpenEnd = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                showActiveMomentView = true
            }
        } else if url.host == "capture" {
            let modeParam = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "mode" })?
                .value ?? "photo"

            let targetType: FragmentType
            switch modeParam {
            case "video": targetType = .video
            case "note":  targetType = .note
            case "audio", "memo": targetType = .audio
            default:      targetType = .photo
            }

            showActiveMomentView = false
            activeMomentAutoOpenEnd = false
            activeMomentInitialCaptureType = targetType
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                showActiveMomentView = true
            }
        } else if url.host == "moment" {
            activeMomentInitialCaptureType = nil
            activeMomentAutoOpenEnd = false
            showActiveMomentView = true
        }
    }

    // MARK: - Active Session Floating Island Banner (Tapping brings back ActiveMomentView)
    private var activeSessionFloatingIsland: some View {
        Group {
            if let session = momentManager.activeSession {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showActiveMomentView = true
                } label: {
                    HStack(spacing: 14) {
                        // ThinkingOrb working state
                        ThinkingOrb(state: .connecting, size: 48)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Text("Moment Active")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)

                                TimelineView(.periodic(from: .now, by: 1.0)) { context in
                                    Text(session.formattedElapsed(at: context.date))
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Text(session.fragmentCount == 0 ? "Tap to open Moment" : "\(session.fragmentCountText) captured")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        // Discard active moment button
                        Button(role: .destructive) {
                            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                            showDiscardConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.red)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .clipShape(Circle())
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.glass)
                .padding(.horizontal, 20)
            }
        }
    }

    private func handleFragmentCaptured(_ newFragment: Fragment) {
        if momentManager.isSessionActive {
            // ONLY add to active moment session (do not store in standalone FragmentsView)
            momentManager.addFragment(newFragment)
        } else {
            // Standalone quick capture outside any moment session
            incomingNewFragment = newFragment
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                selectedTab = .fragments
                activeTab = .fragments
            }
        }
    }
}

#if DEBUG
#Preview("ContentView - Light") {
    ContentView()
}

#Preview("ContentView - Dark") {
    ContentView()
        .preferredColorScheme(.dark)
}
#endif
