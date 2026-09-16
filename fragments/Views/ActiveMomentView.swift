//
//  ActiveMomentView.swift
//  fragments
//
//  Created on 9/15/26.
//

import SwiftUI

struct ActiveMomentView: View {
    var onDismiss: () -> Void
    var onSaveComplete: () -> Void

    @State private var viewModel: ActiveMomentViewModel
    @Environment(\.colorScheme) private var colorScheme

    init(
        momentManager: MomentManager = MomentManager.shared,
        initialCaptureType: FragmentType? = nil,
        autoOpenEnd: Bool = false,
        onDismiss: @escaping () -> Void,
        onSaveComplete: @escaping () -> Void
    ) {
        self.onDismiss = onDismiss
        self.onSaveComplete = onSaveComplete
        self._viewModel = State(initialValue: ActiveMomentViewModel(
            momentManager: momentManager,
            initialCaptureType: initialCaptureType,
            autoOpenEnd: autoOpenEnd
        ))
    }

    var body: some View {
        ZStack {
            NavigationStack {
                ZStack(alignment: .bottom) {
                    // Dark / Atmospheric background canvas
                    Color(uiColor: .systemBackground).ignoresSafeArea()

                    if let currentSession = viewModel.session {
                        VStack(spacing: 0) {
                            // 1. Top Session Status Header
                            sessionHeader(session: currentSession)

                            // 2. Middle 3D Spatial Sphere
                            ZStack {
                                if !currentSession.fragments.isEmpty {
                                    FragmentSphere(
                                        fragments: currentSession.fragments,
                                        onSelectFragment: { frag in
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                                                viewModel.selectedFragment = frag
                                            }
                                        }
                                    )
                                    .transition(.opacity)
                                } else {
                                    emptySessionGuide
                                        .transition(.opacity)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                            // Bottom Spacer to avoid overlapping with bottom floating orb
                            Spacer()
                                .frame(height: 100)
                        }

                        // 3. Floating Orb Dock at the Bottom
                        bottomFloatingOrbDock(session: currentSession)
                            .zIndex(50)
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onDismiss()
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 14, weight: .bold))
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            viewModel.showEndMomentSheet = true
                        } label: {
                            Text("Save Moment")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                        }
                        .buttonStyle(.glassProminent)
                        .tint(.primary)
                        .shadow(color: Color.red.opacity(0.35), radius: 5, y: 2)
                    }
                }
            }
            .blur(radius: viewModel.selectedFragment != nil ? 20 : 0)
            .animation(.easeInOut(duration: 0.28), value: viewModel.selectedFragment != nil)

            // Fragment Detail Modal
            if let frag = viewModel.selectedFragment {
                FragmentDetailView(
                    fragment: frag,
                    onDelete: { fragmentToDelete in
                        viewModel.deleteFragmentFromSession(fragmentToDelete)
                    },
                    onDismiss: {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                            viewModel.dismissSelectedFragment()
                        }
                    }
                )
                .transition(.opacity)
                .zIndex(100)
            }
        }
        // Direct FullScreenCover for CaptureView from within ActiveMomentView
        .fullScreenCover(isPresented: $viewModel.showCaptureSheet) {
            CaptureView(
                initialMode: {
                    switch viewModel.captureInitialType {
                    case .photo: return .photo
                    case .video: return .video
                    case .note: return .note
                    case .audio: return .memo
                    }
                }(),
                activeSession: viewModel.momentManager.activeSession,
                onCaptureFragment: { newFragment in
                    viewModel.handleCapturedFragment(newFragment)
                },
                onClose: {
                    viewModel.showCaptureSheet = false
                },
                onEndActiveMoment: {
                    viewModel.showCaptureSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        viewModel.showEndMomentSheet = true
                    }
                }
            )
        }
        // Direct Sheet for EndMomentSheet from within ActiveMomentView
        .sheet(isPresented: $viewModel.showEndMomentSheet) {
            if let currentSession = viewModel.momentManager.activeSession {
                EndMomentSheet(
                    session: currentSession,
                    onSave: { name, category, color, location in
                        viewModel.momentManager.finishSession(
                            name: name,
                            category: category,
                            color: color,
                            location: location
                        )
                        viewModel.showEndMomentSheet = false
                        onSaveComplete()
                    },
                    onCancel: {
                        viewModel.momentManager.cancelSession()
                        viewModel.showEndMomentSheet = false
                        onDismiss()
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
            }
        }
        .onChange(of: viewModel.initialCaptureType) { _, newType in
            if let newType = newType {
                viewModel.openCaptureSheet(type: newType)
            }
        }
        .onChange(of: viewModel.autoOpenEnd) { _, shouldOpen in
            if shouldOpen {
                viewModel.showEndMomentSheet = true
            }
        }
    }

    // MARK: - Top Session Header
    private func sessionHeader(session: MomentSession) -> some View {
        HStack(spacing: 12) {

            // Live Elapsed Time
            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                TimelineView(.periodic(from: .now, by: 1.0)) { context in
                    Text(session.formattedElapsed(at: context.date))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                }
            }

            Spacer()

            // Fragment Count
            HStack(spacing: 4) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Text(session.fragmentCountText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    // MARK: - Bottom Floating ThinkingOrb Dock
    private func bottomFloatingOrbDock(session: MomentSession) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            viewModel.openCaptureSheet(type: .photo)
        } label: {
            HStack(spacing: 14) {
                // Floating ThinkingOrb (working state)

                ThinkingOrb(state: .connecting, size: 48)
                

                VStack(alignment: .leading, spacing: 2) {
                    Text("Capture Fragment")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("Tap to add fragments...")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
        }
        .buttonStyle(.glass)
        .padding(.horizontal, 24)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                viewModel.orbPulse = true
            }
        }
    }

    // MARK: - Empty Session Guide
    private var emptySessionGuide: some View {
        VStack(spacing: 20) {
            ZStack {
                // Orbital guide rings
                Circle()
                    .stroke(Color.primary.opacity(0.1), style: StrokeStyle(lineWidth: 1.5, dash: [4, 6]))
                    .frame(width: 220, height: 220)

                Circle()
                    .stroke(Color.primary.opacity(0.09), style: StrokeStyle(lineWidth: 1, dash: [3, 8]))
                    .frame(width: 290, height: 290)

                Image(systemName: "sparkles")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.primary)
            }
        }
    }
}

#if DEBUG
#Preview {
    ActiveMomentView(
        momentManager: {
            let manager = MomentManager()
            manager.activeSession = MomentSession(
                startDate: Date(),
                fragments: [
                    Fragment(type: .photo, title: "Coffee Art", subtitle: "02:15 PM"),
                    Fragment(type: .note, title: "Idea snippet", subtitle: "02:18 PM")
                ],
                location: "Jakarta, ID"
            )
            return manager
        }(),
        onDismiss: {},
        onSaveComplete: {}
    )
}
#endif
