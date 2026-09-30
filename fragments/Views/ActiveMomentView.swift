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
    var initialCaptureType: FragmentType?
    var autoOpenEnd: Bool

    @State private var viewModel: ActiveMomentViewModel
    @State private var copiedCodeFeedback: Bool = false
    @State private var showLeaveConfirmation: Bool = false
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
        self.initialCaptureType = initialCaptureType
        self.autoOpenEnd = autoOpenEnd
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
                                .foregroundStyle(.primary)
                        }
                    }
                    
                    ToolbarItem(placement: .topBarTrailing) {
                            if viewModel.session?.isShared == true {
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    viewModel.showAddPeopleSheet = true
                                } label: {
                                    Image(systemName: "person.badge.plus")
                                        .font(.system(size: 13, weight: .bold))
                                }
                            }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        if viewModel.isHost {
                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                viewModel.showEndMomentSheet = true
                            } label: {
                                Text("Save Moment")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                            }
                            .glassProminentButtonStyle()
                            .tint(.primary)
                        } else {
                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                showLeaveConfirmation = true
                            } label: {
                                Text("Leave Moment")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                            }
                            .glassProminentButtonStyle()
                            .tint(.red)
                        }
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
                    authorName: viewModel.session?.isShared == true
                        ? RoomManager.shared.authorName(
                            forFragmentID: frag.id.uuidString,
                            roomID: viewModel.session?.room?.id
                        )
                        : nil,
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
                captureContext: {
                    if let room = viewModel.session?.room, viewModel.session?.isShared == true {
                        return .room(room)
                    }
                    return .personal
                }(),
                onCaptureFragment: { newFragment in
                    viewModel.handleCapturedFragment(newFragment)
                },
                onCaptureSharedFragment: { sharedFragment in
                    viewModel.handleCapturedSharedFragment(sharedFragment)
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
        // Add People Sheet for Shared Moment
        .sheet(isPresented: $viewModel.showAddPeopleSheet) {
            if let room = viewModel.session?.room {
                RoomMembersSheet(room: room)
            }
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
        .alert(
            "Moment Limit Reached",
            isPresented: $viewModel.showLimitAlert
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("A moment can contain a maximum of 15 fragments. You have reached the limit for this moment.")
        }
        .alert(
            "Leave Moment?",
            isPresented: $showLeaveConfirmation
        ) {
            Button("Cancel", role: .cancel) { }
            Button("Leave", role: .destructive) {
                viewModel.leaveSession()
                onDismiss()
            }
        } message: {
            Text("Are you sure you want to leave this shared moment? The host can continue and save the moment.")
        }
        .onChange(of: viewModel.momentManager.activeSession == nil) { _, isNil in
            if isNil {
                onDismiss()
            }
        }
        .onAppear {
            viewModel.startSyncObserver()
            if let initType = initialCaptureType {
                viewModel.openCaptureSheet(type: initType)
            } else if autoOpenEnd {
                viewModel.showEndMomentSheet = true
            }
        }
        .onChange(of: initialCaptureType) { _, newType in
            if let newType {
                viewModel.openCaptureSheet(type: newType)
            }
        }
        .onChange(of: autoOpenEnd) { _, shouldOpenEnd in
            if shouldOpenEnd {
                viewModel.showEndMomentSheet = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenActiveMomentCapture"))) { notif in
            if let type = notif.object as? FragmentType {
                viewModel.openCaptureSheet(type: type)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RequestEndMoment"))) { _ in
            viewModel.showCaptureSheet = false
            viewModel.showEndMomentSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RequestLeaveMoment"))) { _ in
            viewModel.showCaptureSheet = false
            showLeaveConfirmation = true
        }
        .onDisappear {
            viewModel.stopSyncObserver()
        }
    }

    // MARK: - Top Session Header
    private func sessionHeader(session: MomentSession) -> some View {
        HStack(spacing: 10) {
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

            if session.isShared, let room = session.room {
                // Join credential is server-assigned (Room.shareRecordID). Never
                // fall back to a room-ID-derived value: knowing room_id must not
                // reveal the join code. Supabase pill renders only when a real
                // code exists; CloudKit keeps its existing prefix(8) lookup tag.
                if room.backend == .supabase {
                    if let code = room.shareRecordID, !code.isEmpty {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            UIPasteboard.general.string = code
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                copiedCodeFeedback = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    copiedCodeFeedback = false
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: copiedCodeFeedback ? "checkmark.circle.fill" : "number")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(copiedCodeFeedback ? .green : .secondary)
                                Text(copiedCodeFeedback ? "Copied" : code)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(copiedCodeFeedback ? .green : .primary)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    let shortCode = String(room.id.prefix(8)).uppercased()
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        UIPasteboard.general.string = shortCode
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            copiedCodeFeedback = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                copiedCodeFeedback = false
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: copiedCodeFeedback ? "checkmark.circle.fill" : "number")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(copiedCodeFeedback ? .green : .secondary)
                            Text(copiedCodeFeedback ? "Copied" : shortCode)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(copiedCodeFeedback ? .green : .primary)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            // Fragment Count
            HStack(spacing: 4) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(session.isAtCapacity && !session.isShared ? .orange : .secondary)

                Text(session.isShared
                     ? "\(session.fragmentCount) \(session.fragmentCount == 1 ? "fragment" : "fragments")"
                     : "\(session.fragmentCount)/\(MomentSession.maxFragments) fragments")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(session.isAtCapacity && !session.isShared ? .orange : .primary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    // MARK: - Bottom Floating ThinkingOrb Dock
    private func bottomFloatingOrbDock(session: MomentSession) -> some View {
        let isFull = session.isAtCapacity && !session.isShared

        return Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            if isFull {
                viewModel.showLimitAlert = true
            } else {
                viewModel.openCaptureSheet(type: .photo)
            }
        } label: {
            HStack(spacing: 14) {
                // Floating ThinkingOrb (working state)
                ThinkingOrb(state: .connecting, size: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text(isFull ? "Limit Reached" : (session.isShared ? "Capture Fragment" : "Capture Fragment"))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text(isFull ? "Max 15 fragments reached" :  "Tap to add fragments...")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isFull ? "exclamationmark.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(isFull ? .orange : .primary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .floatingDockButtonStyle()
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
