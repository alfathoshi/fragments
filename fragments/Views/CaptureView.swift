//
//  CaptureView.swift
//  fragments
//
//  Created by Muhammad Bintang Al-Fath on 9/12/26.
//

import SwiftUI

public enum CaptureMode: String, CaseIterable, Identifiable {
    case photo
    case video
    case note
    case memo

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .photo: return "Photo"
        case .video: return "Video"
        case .note: return "Note"
        case .memo: return "Memo"
        }
    }

    public var icon: String {
        switch self {
        case .photo: return "camera.fill"
        case .video: return "video.fill"
        case .note: return "square.and.pencil"
        case .memo: return "waveform"
        }
    }
}

public struct CaptureView: View {
    public var isActive: Bool = true
    public var onClose: (() -> Void)? = nil
    public var onEndActiveMoment: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var viewModel: CaptureViewModel
    @Namespace private var modeAnimation
    @State private var ambientGlow: CGFloat = 0.4

    public init(
        isActive: Bool = true,
        initialMode: CaptureMode = .photo,
        activeMoment: FolderCollection? = nil,
        activeSession: MomentSession? = nil,
        onCaptureFragment: ((Fragment) -> Void)? = nil,
        onClose: (() -> Void)? = nil,
        onEndActiveMoment: (() -> Void)? = nil
    ) {
        self.isActive = isActive
        self._viewModel = State(initialValue: CaptureViewModel(
            initialMode: initialMode,
            activeMoment: activeMoment,
            activeSession: activeSession,
            onCaptureFragment: onCaptureFragment
        ))
        self.onClose = onClose
        self.onEndActiveMoment = onEndActiveMoment
    }


    public var body: some View {
        NavigationStack {
            ZStack {
                // Adaptive camera chassis background
                Color(uiColor: .systemBackground).ignoresSafeArea()

                VStack(spacing: 8) {
                    // 1. Segmented Control
                    segmentedModeControl

                    Spacer()

                    // 3. Mode Content (Photo / Video / Note / Memo)
                    ZStack {
                        switch viewModel.selectedMode {
                        case .photo:
                            CustomCamera(
                                isActive: isActive,
                                onCapturedPhoto: { image, fileURL in
                                    viewModel.handlePhotoCapture(image: image, fileURL: fileURL)
                                },
                                onClose: onClose
                            )
                            .id(CaptureMode.photo)
                            .transition(.opacity)

                        case .video:
                            CustomVideoCamera(
                                isActive: isActive,
                                onCapturedVideo: { url, duration in
                                    viewModel.handleVideoCapture(url: url, duration: duration)
                                },
                                onClose: onClose
                            )
                            .id(CaptureMode.video)
                            .transition(.opacity)

                        case .note:
                            CustomNoteView(
                                onSaveNote: { title, text, color in
                                    viewModel.handleNoteCapture(title: title, text: text, color: color)
                                },
                                onClose: onClose
                            )
                            .id(CaptureMode.note)
                            .transition(.opacity)

                        case .memo:
                            CustomMemoView(
                                onSaveMemo: { fileURL, duration, waveform, title, color in
                                    viewModel.handleMemoCapture(fileURL: fileURL, duration: duration, waveform: waveform, title: title, color: color)
                                },
                                onClose: onClose
                            )
                            .id(CaptureMode.memo)
                            .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(.easeInOut(duration: 0.20), value: viewModel.selectedMode)
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 16)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if onClose != nil {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            if let onClose = onClose {
                                onClose()
                            } else {
                                dismiss()
                            }
                        } label: {
                            Image(systemName: "chevron.backward")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(colorScheme == .dark ? Color.white : Color(red: 0.12, green: 0.12, blue: 0.14))
                        }
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: - Segmented Mode Control

    private var segmentedModeControl: some View {
        HStack(spacing: 0) {
            ForEach(CaptureMode.allCases) { mode in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        viewModel.selectedMode = mode
                    }
                } label: {
                    Text(mode.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(viewModel.selectedMode == mode ? (colorScheme == .dark ? Color.white : Color(red: 0.12, green: 0.12, blue: 0.14)) : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            if viewModel.selectedMode == mode {
                                Capsule()
                                    .fill(colorScheme == .dark ? Color(red: 0.22, green: 0.22, blue: 0.24) : Color.white)
                                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.14), radius: 5, x: 0, y: 2)
                                    .matchedGeometryEffect(id: "ACTIVE_MODE_CAPSULE", in: modeAnimation)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity)
        .background(colorScheme == .dark ? Color(red: 0.12, green: 0.12, blue: 0.14) : Color(red: 0.94, green: 0.94, blue: 0.96), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06), lineWidth: 0.8)
        )
    }

    // MARK: - Active Session Banner with ThinkingOrb

    private func activeSessionBanner(session: MomentSession) -> some View {
        HStack(spacing: 10) {
            // ThinkingOrb in 'working' state
            ThinkingOrb(state: .connecting, size: 28)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text("Moment in Progress")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("•")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 10))

                    TimelineView(.periodic(from: .now, by: 1.0)) { context in
                        Text(session.formattedElapsed(at: context.date))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(session.fragmentCount == 0 ? "Capturing fragments..." : "\(session.fragmentCount) captured")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let onEnd = onEndActiveMoment {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onEnd()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 8))
                        Text("End")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.red, in: Capsule())
                    .shadow(color: Color.red.opacity(0.3), radius: 4, y: 1.5)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
    }

    // MARK: - Active Moment Indicator Pill

    private func activeMomentPill(moment: FolderCollection) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.red)
                .frame(width: 7, height: 7)

            Text("Active Moment: \(moment.name)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(colorScheme == .dark ? Color.white : Color(red: 0.15, green: 0.15, blue: 0.18))

            if let onEnd = onEndActiveMoment {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onEnd()
                } label: {
                    Text("End")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Color.red.opacity(colorScheme == .dark ? 0.25 : 0.12), in: Capsule())
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(colorScheme == .dark ? Color(red: 0.16, green: 0.16, blue: 0.18) : Color(red: 0.95, green: 0.95, blue: 0.97), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.red.opacity(colorScheme == .dark ? 0.35 : 0.15), lineWidth: 0.8)
        )
    }




}

#if DEBUG
#Preview("CaptureView - Light Mode") {
    CaptureView()
}

#Preview("CaptureView - Dark Mode") {
    CaptureView()
        .preferredColorScheme(.dark)
}
#endif
