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
    @State private var viewModel = ContentViewModel()

    var body: some View {
        ZStack(alignment: .bottom) {
            // Native TabView (Blurred when Capture Menu or Fragment Detail is Open)
            TabView(selection: $viewModel.selectedTab) {
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
                        incomingNewFragment: $viewModel.incomingNewFragment,
                        selectedFragment: $viewModel.selectedFragment
                    )
                } label: {
                    Label {
                        Text("Fragments")
                    } icon: {
                        Image(systemName: viewModel.currentTab == .fragments ? "circle.hexagongrid.fill" : "circle.hexagongrid")
                            .environment(\.symbolVariants, .none)
                    }
                    .environment(\.symbolVariants, .none)
                    .id("tab_fragments_\(viewModel.currentTab == .fragments)")
                }

                Tab(value: AppTab.logs) {
                    MomentsView(momentManager: viewModel.momentManager)
                } label: {
                    Label {
                        Text("Moments")
                    } icon: {
                        Image(systemName: viewModel.currentTab == .logs ? "rectangle.stack.fill" : "rectangle.stack")
                            .environment(\.symbolVariants, .none)
                    }
                    .environment(\.symbolVariants, .none)
                    .id("tab_moments_\(viewModel.currentTab == .logs)")
                }
            }
            .tint(.primary)
            .blur(radius: (viewModel.isCaptureMenuOpen || viewModel.selectedFragment != nil) ? 1 : 0)
            .animation(.easeInOut(duration: 0.28), value: viewModel.isCaptureMenuOpen || viewModel.selectedFragment != nil)

            // Floating Active Session Orb Widget (When moment is active and ActiveMomentView is minimized - at bottom above tab bar)
            if viewModel.momentManager.isSessionActive && !viewModel.showActiveMomentView && viewModel.selectedTab != .capture && viewModel.selectedFragment == nil {
                activeSessionFloatingIsland
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 64)
                    .zIndex(40)
            }

            // Floating 3D Orbs Capture Overlay
            if viewModel.isCaptureMenuOpen {
                FloatingCaptureOverlay(
                    isOpen: $viewModel.isCaptureMenuOpen,
                    onSelectStartMoment: {
                        if viewModel.momentManager.isSessionActive {
                            viewModel.showResumeOrNewMomentAlert = true
                        } else {
                            viewModel.momentManager.startSession()
                            viewModel.showActiveMomentView = true
                        }
                    },
                    onSelectQuickCaptureType: { type in
                        if viewModel.momentManager.isSessionActive {
                            viewModel.pendingQuickCaptureType = type
                            viewModel.showDiscardForQuickCaptureAlert = true
                        } else {
                            viewModel.momentManager.cleanupExpiredStandaloneFragments()
                            if viewModel.momentManager.standaloneFragments.count >= MomentManager.maxStandaloneFragments {
                                viewModel.showStandaloneLimitAlert = true
                            } else {
                                viewModel.quickCaptureInitialType = type
                                viewModel.showQuickCaptureSheet = true
                            }
                        }
                    }
                )
                .transition(.opacity)
                .zIndex(50)
            }

            // Fragment Detail Focused Preview Modal (Overlays TabBar, Navigation bar, and entire window)
            if let fragment = viewModel.selectedFragment {
                FragmentDetailView(
                    fragment: fragment,
                    onDelete: { frag in
                        NotificationCenter.default.post(name: NSNotification.Name("DeleteFragment"), object: frag)
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                            viewModel.selectedFragment = nil
                        }
                    },
                    onDismiss: {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                            viewModel.selectedFragment = nil
                        }
                    }
                )
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: viewModel.momentManager.activeSession != nil)
        .onChange(of: viewModel.selectedTab) { oldTab, newTab in
            if newTab == .capture {
                viewModel.handleCaptureTabTap(oldTab: oldTab)
            } else {
                viewModel.activeTab = newTab
            }
        }
        // Active Moment View (Full Spatial Screen with Bottom Floating ThinkingOrb)
        .fullScreenCover(isPresented: $viewModel.showActiveMomentView) {
            ActiveMomentView(
                momentManager: viewModel.momentManager,
                initialCaptureType: viewModel.activeMomentInitialCaptureType,
                autoOpenEnd: viewModel.activeMomentAutoOpenEnd,
                onDismiss: {
                    viewModel.onActiveMomentDismiss()
                },
                onSaveComplete: {
                    viewModel.onSaveComplete()
                }
            )
        }
        // Quick Capture Sheet (For standalone quick captures outside active moment)
        .fullScreenCover(isPresented: $viewModel.showQuickCaptureSheet) {
            CaptureView(
                initialMode: {
                    switch viewModel.quickCaptureInitialType {
                    case .photo: return .photo
                    case .video: return .video
                    case .note: return .note
                    case .audio: return .memo
                    }
                }(),
                activeSession: viewModel.momentManager.activeSession,
                onCaptureFragment: { newFragment in
                    viewModel.handleFragmentCaptured(newFragment)
                    viewModel.showQuickCaptureSheet = false
                },
                onClose: {
                    viewModel.showQuickCaptureSheet = false
                },
                onEndActiveMoment: {
                    viewModel.showQuickCaptureSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        viewModel.momentManager.requestEndSession()
                    }
                }
            )
        }
        // End Moment Sheet fallback
        .sheet(isPresented: $viewModel.momentManager.showEndMomentSheet) {
            if let session = viewModel.momentManager.activeSession {
                EndMomentSheet(
                    session: session,
                    onSave: { name, category, color, location in
                        viewModel.momentManager.finishSession(
                            name: name,
                            category: category,
                            color: color,
                            location: location
                        )
                        viewModel.showActiveMomentView = false
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            viewModel.selectedTab = .logs
                            viewModel.activeTab = .logs
                        }
                    },
                    onCancel: {
                        viewModel.momentManager.cancelSession()
                        viewModel.showActiveMomentView = false
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
            }
        }
        .alert(
            "Discard Moment?",
            isPresented: $viewModel.showDiscardConfirmation
        ) {
            Button("Cancel", role: .cancel) { }
            Button("Discard", role: .destructive) {
                viewModel.discardMoment()
            }
        } message: {
            Text("Are you sure you want to discard this moment? Any captured fragments will not be saved.")
        }
        // Confirmation when starting a moment while one is already active
        .alert(
            "Moment in Progress",
            isPresented: $viewModel.showResumeOrNewMomentAlert
        ) {
            Button("Resume Moment") {
                viewModel.resumeMoment()
            }
            Button("Start New Moment", role: .destructive) {
                viewModel.startNewMoment()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You already have an active moment. Would you like to resume it, or discard it and start a new moment?")
        }
        // Confirmation when starting quick capture while moment is active
        .alert(
            "Discard Active Moment?",
            isPresented: $viewModel.showDiscardForQuickCaptureAlert
        ) {
            Button("Cancel", role: .cancel) { }
            Button("Discard", role: .destructive) {
                viewModel.discardForQuickCapture()
            }
        } message: {
            Text("Starting a quick capture will discard your currently active moment. Any captured fragments will not be saved.")
        }
        .alert(
            "Fragment Limit Reached",
            isPresented: $viewModel.showStandaloneLimitAlert
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("You can keep up to 15 fragments in Fragments. Standalone fragments disappear after 24 hours, or you can delete some to capture more.")
        }
        .alert(
            "Moment Limit Reached",
            isPresented: $viewModel.showMomentLimitAlert
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("A moment can contain a maximum of 15 fragments. You have reached the limit for this moment.")
        }
        .onAppear {
            viewModel.setModelContext(modelContext)
        }
        .onOpenURL { url in
            viewModel.handleDeepLink(url)
        }
    }

    // MARK: - Active Session Floating Island Banner (Tapping brings back ActiveMomentView)
    private var activeSessionFloatingIsland: some View {
        Group {
            if let session = viewModel.momentManager.activeSession {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    viewModel.showActiveMomentView = true
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
                            viewModel.showDiscardConfirmation = true
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
