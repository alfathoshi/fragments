//
//  CustomMemoView.swift
//  fragments
//
//  Created on 9/14/26.
//

import SwiftUI
import AVFoundation
internal import Combine

public struct CustomMemoView: View {
    // MARK: - Callbacks

    public var onSaveMemo: ((URL?, TimeInterval, [CGFloat], String, Color) -> Void)? = nil
    public var onClose: (() -> Void)? = nil

    // MARK: - Audio Recorder Service

    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var recorder = AudioRecorderManager()

    // MARK: - Memo Title & Color State

    @State private var memoTitle: String = ""
    @State private var selectedColorIndex: Int = 0
    @FocusState private var isTitleFocused: Bool

    // MARK: - Color Palette

    public struct MemoColorOption: Identifiable {
        public let id = UUID()
        public let name: String
        public let color: Color
        public let gradient: [Color]
    }

    private let colorOptions: [MemoColorOption] = [
        MemoColorOption(
            name: "Electric Blue",
            color: Color(red: 0.0, green: 0.533, blue: 1.0),
            gradient: [Color(red: 0.0, green: 0.533, blue: 1.0), Color(red: 0.10, green: 0.40, blue: 0.90)]
        ),
        MemoColorOption(
            name: "Butterscotch",
            color: Color(red: 1.0, green: 0.859, blue: 0.576),
            gradient: [Color(red: 1.0, green: 0.859, blue: 0.576), Color(red: 0.98, green: 0.76, blue: 0.45)]
        ),
        MemoColorOption(
            name: "Mint",
            color: Color(red: 0.35, green: 0.88, blue: 0.60),
            gradient: [Color(red: 0.35, green: 0.88, blue: 0.60), Color(red: 0.20, green: 0.75, blue: 0.50)]
        ),
        MemoColorOption(
            name: "Lavender",
            color: Color(red: 0.75, green: 0.55, blue: 0.98),
            gradient: [Color(red: 0.75, green: 0.55, blue: 0.98), Color(red: 0.60, green: 0.40, blue: 0.90)]
        ),
        MemoColorOption(
            name: "Sunset Coral",
            color: Color(red: 1.0, green: 0.35, blue: 0.45),
            gradient: [Color(red: 1.0, green: 0.35, blue: 0.45), Color(red: 0.95, green: 0.20, blue: 0.35)]
        )
    ]

    private var activeColor: MemoColorOption {
        colorOptions[selectedColorIndex]
    }

    // MARK: - Dimensions (matching CustomCamera chassis)

    private let cardCornerRadius: CGFloat = 47
    private let viewportCornerRadius: CGFloat = 31
    private let maxRecordingDuration: Double = 5.0

    // MARK: - Initializer

    public init(
        onSaveMemo: ((URL?, TimeInterval, [CGFloat], String, Color) -> Void)? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.onSaveMemo = onSaveMemo
        self.onClose = onClose
    }

    public init(
        onSaveMemo: @escaping (URL?, TimeInterval, [CGFloat]) -> Void,
        onClose: (() -> Void)? = nil
    ) {
        self.onSaveMemo = { fileURL, duration, waveform, _, _ in
            onSaveMemo(fileURL, duration, waveform)
        }
        self.onClose = onClose
    }

    // MARK: - Body

    public var body: some View {
        ZStack {
            // Card Chassis Background
            (colorScheme == .dark ? Color(red: 0.11, green: 0.11, blue: 0.13) : Color.white)

            // Main Card Layout: Top Bar + Viewport Canvas + Bottom Controls Bar
            VStack(spacing: 16) {
                // Top: Title Input & Color Selector Bar
                titleAndColorBar
                    .frame(height: 74)

                // 1. Audio Waveform Viewport
                viewportCanvas
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // 2. Bottom Controls Bar (Reset/Trash + Record/Play + Save)
                bottomControlsBar
                    .frame(height: 74)
                    .padding(.bottom, 2)
            }
            .padding(16)
        }
        .frame(maxWidth: 386, maxHeight: 804)
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        // Matching drop shadows from CustomCamera / CustomVideoCamera / CustomNoteView
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.18), radius: 8, x: 0, y: 3.5)
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.20 : 0.08), radius: 2, x: 0, y: 1.0)
        // Specular Inner Bevel / Rim Highlight
        .overlay {
            let isDark = colorScheme == .dark
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: isDark ? [
                            .init(color: Color.white.opacity(0.20), location: 0.0),
                            .init(color: Color.white.opacity(0.06), location: 0.25),
                            .init(color: Color.white.opacity(0.02), location: 0.85),
                            .init(color: Color.black.opacity(0.30), location: 1.0)
                        ] : [
                            .init(color: Color.white.opacity(0.95), location: 0.0),
                            .init(color: Color(red: 0.90, green: 0.90, blue: 0.92), location: 0.25),
                            .init(color: Color(red: 0.85, green: 0.85, blue: 0.88), location: 0.85),
                            .init(color: Color.black.opacity(0.06), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.5
                )
        }
        .onDisappear {
            recorder.stopRecording()
            recorder.stopPlayback()
        }
    }

    // MARK: - 0. Title & Color Palette Bar

    private var titleAndColorBar: some View {
        let isDark = colorScheme == .dark

        return HStack(spacing: 10) {
            // Waveform Icon in Active Color
            Image(systemName: "waveform")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(activeColor.color)

            // Title TextField
            TextField("Memo Title...", text: $memoTitle)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.primary)
                .focused($isTitleFocused)
                .submitLabel(.done)
                .onSubmit {
                    isTitleFocused = false
                }

            Spacer(minLength: 4)

            // Color Swatches
            HStack(spacing: 6) {
                ForEach(0..<colorOptions.count, id: \.self) { idx in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                            selectedColorIndex = idx
                        }
                    } label: {
                        Circle()
                            .fill(colorOptions[idx].color)
                            .frame(width: selectedColorIndex == idx ? 20 : 15, height: selectedColorIndex == idx ? 20 : 15)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white, lineWidth: selectedColorIndex == idx ? 2 : 1)
                            )
                            .shadow(color: Color.black.opacity(0.15), radius: 2, y: 1)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(isDark ? Color(red: 0.18, green: 0.18, blue: 0.20) : Color(red: 0.949, green: 0.949, blue: 0.969), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.06), lineWidth: 0.8)
        )
    }

    // MARK: - 1. Viewport Canvas (Fluid viewport, cornerRadius: 31)

    private var viewportCanvas: some View {
        ZStack {
            // Backdrop Canvas: adaptive dark graphite in dark mode / #8E8E93 in light mode
            RoundedRectangle(cornerRadius: viewportCornerRadius, style: .continuous)
                .fill(colorScheme == .dark ? Color(red: 0.16, green: 0.16, blue: 0.18) : Color(red: 0.557, green: 0.557, blue: 0.576))

            // 5-Second Active Recording Perimeter Border Surrounding Viewport
            if recorder.isRecording {
                // Subtle track channel along perimeter
                RoundedRectangle(cornerRadius: viewportCornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.20), lineWidth: 4.0)

                // Glowing progress stroke traveling around perimeter using selected color
                RoundedRectangle(cornerRadius: viewportCornerRadius, style: .continuous)
                    .trim(from: 0.0, to: min(CGFloat(recorder.elapsedTime / maxRecordingDuration), 1.0))
                    .stroke(
                        LinearGradient(
                            colors: activeColor.gradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 4.0, lineCap: .round)
                    )
                    .shadow(color: activeColor.color.opacity(0.65), radius: 6)
                    .animation(.linear(duration: 0.05), value: recorder.elapsedTime)
            }

            // Top Status Overlay (Elapsed Time / Recording Pill)
            VStack {
                HStack {
                    if recorder.isRecording {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(red: 1.0, green: 0.176, blue: 0.333)) // #FF2D55
                                .frame(width: 8, height: 8)
                                .opacity(recorder.isBlinking ? 1.0 : 0.3)
                                .animation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true), value: recorder.isBlinking)

                            Text(String(format: "00:0%d / 05s", min(Int(recorder.elapsedTime), 5)))
                                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.50), in: Capsule())
                        .transition(.scale.combined(with: .opacity))
                    } else if recorder.hasRecordedAudio {
                        HStack(spacing: 6) {
                            Image(systemName: recorder.isPlaying ? "speaker.wave.2.fill" : "checkmark.circle.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color(red: 0.0, green: 0.533, blue: 1.0))

                            Text(recorder.isPlaying ? "Playing memo..." : "Recorded (5s)")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.40), in: Capsule())
                        .transition(.scale.combined(with: .opacity))
                    } else {
                        // Subtle Guide Tag
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color.white.opacity(0.6))
                                .frame(width: 5, height: 5)
                            Text("5s VOICE MEMO")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.25), in: Capsule())
                    }

                    Spacer()
                }
                .padding(18)

                Spacer()
            }

            // Waveform Display Area
            waveformCanvasArea
                .padding(.horizontal, 16)
        }
        .clipShape(RoundedRectangle(cornerRadius: viewportCornerRadius, style: .continuous))
    }

    // MARK: - Waveform Canvas Area (No wave initially, stationary progressive wave while recording & playing)

    @ViewBuilder
    private var waveformCanvasArea: some View {
        if !recorder.isRecording && !recorder.hasRecordedAudio {
            // Initial State: No wave! Subtle center baseline + friendly hint
            VStack(spacing: 12) {
                // Subtle horizontal center baseline
                Rectangle()
                    .fill(Color.white.opacity(0.20))
                    .frame(height: 1.5)
                    .frame(maxWidth: 240)

                Text("Tap record to start 5s memo")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            .transition(.opacity)
        } else {
            // Active Recording or Recorded State: Stationary 45-bar audio waveform
            ZStack(alignment: .leading) {
                // 45 Stationary Bars: FIXED X POSITIONS, ZERO SHAKING!
                HStack(spacing: 4.0) {
                    ForEach(0..<recorder.recordedBars.count, id: \.self) { idx in
                        let barHeight = recorder.recordedBars[idx]
                        let isRecorded = recorder.hasRecordedAudio || idx <= recorder.currentBarIndex
                        let isCurrent = recorder.isRecording && idx == recorder.currentBarIndex
                        let isPlayed = recorder.isPlaying && (Double(idx) / Double(max(1, recorder.recordedBars.count - 1))) <= recorder.playbackProgress

                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(
                                isCurrent
                                    ? activeColor.color
                                    : (isPlayed
                                        ? Color.white
                                        : (isRecorded ? Color.white.opacity(0.85) : Color.white.opacity(0.18)))
                            )
                            .frame(width: 2.8, height: isRecorded ? max(6.0, barHeight) : 6.0)
                            .animation(.linear(duration: 0.05), value: barHeight)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)

                // Playhead indicator when playing
                if recorder.isPlaying {
                    GeometryReader { geo in
                        let playheadX = geo.size.width * CGFloat(recorder.playbackProgress)

                        Rectangle()
                            .fill(activeColor.color)
                            .frame(width: 2.5, height: 140)
                            .shadow(color: activeColor.color.opacity(0.7), radius: 4)
                            .position(x: max(2, min(playheadX, geo.size.width - 2)), y: geo.size.height / 2)
                    }
                    .allowsHitTesting(false)
                }
            }
            .transition(.opacity)
        }
    }

    // MARK: - 2. Bottom Controls Bar (Figma Node 178:2785: 24pt gap)

    private var bottomControlsBar: some View {
        HStack(spacing: 24) {
            // Left: Balancing Slot / Trash Reset Button (56 pt)
            if recorder.hasRecordedAudio && !recorder.isRecording {
                TactileCircularButton(
                    systemImage: "trash",
                    iconColor: Color.red.opacity(0.85),
                    keycapColor: nil,
                    size: 56,
                    iconSize: 18,
                    iconWeight: .semibold
                ) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    recorder.reset()
                }
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Discard Voice Memo")
            } else {
                // Invisible balancing spacer (56 pt, matching right checkmark button)
                Color.clear
                    .frame(width: 56, height: 56)
            }

            // Center: Pink/Red Record Button (Figma Node 178:2789: #FF2D55 Keycap in Milled Socket)
            TactileCircularButton(
                size: 74,
                keycapColor: colorScheme == .dark ? Color(red: 0.20, green: 0.20, blue: 0.22) : Color.white,
                isActive: recorder.isRecording || recorder.isPlaying
            ) {
                if recorder.hasRecordedAudio && !recorder.isRecording {
                    // Play / Pause preview of the 5-second memo
                    recorder.togglePlayback()
                } else {
                    toggleRecording()
                }
            } content: {
                ZStack {
                    if recorder.isRecording {
                        // Red Rounded Stop Square
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(red: 1.0, green: 0.176, blue: 0.333)) // #FF2D55
                            .frame(width: 26, height: 26)
                            .shadow(color: Color(red: 1.0, green: 0.176, blue: 0.333).opacity(0.4), radius: 6)
                            .transition(.scale)
                    } else if recorder.hasRecordedAudio {
                        // Play / Pause preview icon
                        Circle()
                            .fill(Color(red: 1.0, green: 0.176, blue: 0.333)) // #FF2D55
                            .frame(width: 62, height: 62)
                            .shadow(color: Color(red: 1.0, green: 0.176, blue: 0.333).opacity(0.35), radius: 6, y: 2)

                        Image(systemName: recorder.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white)
                            .offset(x: recorder.isPlaying ? 0 : 2)
                    } else {
                        // Red Record Circle (62pt diameter in Figma)
                        Circle()
                            .fill(Color(red: 1.0, green: 0.176, blue: 0.333)) // #FF2D55
                            .frame(width: 62, height: 62)
                            .shadow(color: Color(red: 1.0, green: 0.176, blue: 0.333).opacity(0.35), radius: 6, y: 2)
                            .transition(.scale)
                    }
                }
                .animation(.spring(response: 0.25, dampingFraction: 0.72), value: recorder.isRecording)
                .animation(.spring(response: 0.25, dampingFraction: 0.72), value: recorder.isPlaying)
            }
            .accessibilityLabel(recorder.isRecording ? "Stop Recording (5s Max)" : (recorder.hasRecordedAudio ? "Play / Pause Preview" : "Start Recording Memo (5s Max)"))

            // Right: Blue Checkmark Save Button (Figma Node 178:2874: #0088FF / #08F with White Checkmark)
            TactileCircularButton(
                size: 56,
                keycapColor: Color(red: 0.0, green: 0.533, blue: 1.0), // #08F
                isActive: recorder.hasRecordedAudio || recorder.isRecording
            ) {
                handleSaveMemo()
            } content: {
                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(.white)
            }
            .disabled(!recorder.hasRecordedAudio && !recorder.isRecording)
            .opacity((recorder.hasRecordedAudio || recorder.isRecording) ? 1.0 : 0.45)
            .accessibilityLabel("Save Voice Memo Fragment")
        }
        .animation(.spring(response: 0.30, dampingFraction: 0.75), value: recorder.hasRecordedAudio)
    }

    // MARK: - Actions

    private func toggleRecording() {
        if recorder.isRecording {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            recorder.stopRecording()
        } else {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            recorder.startRecording()
        }
    }

    private func handleSaveMemo() {
        if recorder.isRecording {
            recorder.stopRecording()
        }
        recorder.stopPlayback()

        guard recorder.hasRecordedAudio || recorder.elapsedTime > 0.2 else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }

        UINotificationFeedbackGenerator().notificationOccurred(.success)

        let duration = min(max(recorder.elapsedTime, 1.0), maxRecordingDuration)
        let waveform = recorder.normalizedWaveformSamples()
        let fileURL = recorder.recordedFileURL

        onSaveMemo?(fileURL, duration, waveform, memoTitle, activeColor.color)
    }
}

// MARK: - Audio Recorder Manager (Real Mic + WAV/AAC Playback + Dynamic Realtime Wave)

final class AudioRecorderManager: NSObject, ObservableObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    @Published var isRecording: Bool = false
    @Published var isPlaying: Bool = false
    @Published var elapsedTime: TimeInterval = 0
    @Published var playbackProgress: Double = 0.0
    @Published var hasRecordedAudio: Bool = false
    @Published var isBlinking: Bool = false
    @Published var recordedFileURL: URL? = nil

    static let totalTargetBars: Int = 45
    @Published var recordedBars: [CGFloat] = Array(repeating: 6.0, count: totalTargetBars)
    @Published var currentBarIndex: Int = 0

    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    private let maxDuration: Double = 5.0
    private let tickInterval: Double = 0.05
    private var lastPowerLevel: CGFloat = 0.0
    private var hadHardwareRecorder: Bool = false

    func startRecording() {
        stopPlayback()
        elapsedTime = 0
        playbackProgress = 0.0
        currentBarIndex = 0
        lastPowerLevel = 0.0
        recordedBars = Array(repeating: 6.0, count: Self.totalTargetBars)

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
        } catch {
            print("Audio session setup failed: \(error)")
        }

        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    self?.beginRecordingSession(useHardwareMic: granted)
                }
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    self?.beginRecordingSession(useHardwareMic: granted)
                }
            }
        }
    }

    private func beginRecordingSession(useHardwareMic: Bool) {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("memo_\(UUID().uuidString).m4a")
        recordedFileURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 128000
        ]

        elapsedTime = 0
        isRecording = true
        hasRecordedAudio = false
        isBlinking = true
        hadHardwareRecorder = false

        if useHardwareMic {
            do {
                let recorder = try AVAudioRecorder(url: url, settings: settings)
                recorder.delegate = self
                recorder.isMeteringEnabled = true
                recorder.prepareToRecord()
                let started = recorder.record(forDuration: maxDuration)
                if started {
                    audioRecorder = recorder
                    hadHardwareRecorder = true
                } else {
                    print("AVAudioRecorder.record() failed to start")
                    audioRecorder = nil
                }
            } catch {
                print("Hardware recorder init error: \(error)")
                audioRecorder = nil
            }
        }

        // Live metering timer (20 updates/second for smooth live visualizer)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
            self?.tickRecording()
        }
    }

    private func tickRecording() {
        guard isRecording else { return }

        elapsedTime += tickInterval

        // Calculate stationary bar index (0..<45)
        let slotDuration = maxDuration / Double(Self.totalTargetBars)
        let activeIndex = min(Int(elapsedTime / slotDuration), Self.totalTargetBars - 1)
        currentBarIndex = activeIndex

        // Sample audio volume
        var rawPower: CGFloat = 0.0
        if let recorder = audioRecorder, recorder.isRecording {
            recorder.updateMeters()
            let power = recorder.averagePower(forChannel: 0) // -160 dB to 0 dB, speech is -45 to -10 dB
            let minDb: Float = -48.0
            let clamped = max(minDb, min(0.0, power))
            rawPower = CGFloat((clamped - minDb) / (-minDb))
        } else {
            // Simulated speech pulses if running without hardware mic
            let t = elapsedTime
            let speechPulse = max(0.0, sin(t * 7.5) * 0.45 + sin(t * 14.2) * 0.30 + 0.35)
            rawPower = CGFloat(min(1.0, speechPulse))
        }

        // Attack and decay envelope smoothing
        if rawPower > lastPowerLevel {
            lastPowerLevel = rawPower // Instant attack
        } else {
            lastPowerLevel = max(rawPower, lastPowerLevel * 0.85) // Smooth natural decay
        }

        // Map smoothed level to bar height (6pt to 130pt)
        let barHeight = max(6.0, lastPowerLevel * 128.0)

        // Lock in current bar height
        if activeIndex < recordedBars.count {
            recordedBars[activeIndex] = max(recordedBars[activeIndex], barHeight)
        }

        // Auto-stop at 5.0s
        if elapsedTime >= maxDuration {
            elapsedTime = maxDuration
            stopRecording()
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        timer?.invalidate()
        timer = nil
        audioRecorder?.stop()
        let hadHardware = hadHardwareRecorder
        audioRecorder = nil
        isRecording = false
        hasRecordedAudio = elapsedTime > 0.3
        isBlinking = false

        // Stretch/finalize bars across all 45 slots if stopped early
        finalizeRecordedBars()

        // Cleanly release audio session
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        if !hadHardware {
            ensurePlayableAudioFile()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                guard let self = self, let url = self.recordedFileURL else { return }
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
                if fileSize < 50 {
                    self.ensurePlayableAudioFile()
                }
            }
        }

        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func finalizeRecordedBars() {
        let recordedCount = min(currentBarIndex + 1, Self.totalTargetBars)
        guard recordedCount > 2 else { return }

        // If stopped early, resample recorded bars across all 45 slots so the waveform fills the card
        if recordedCount < Self.totalTargetBars {
            let activeSamples = Array(recordedBars[0..<recordedCount])
            var resampled: [CGFloat] = []
            for i in 0..<Self.totalTargetBars {
                let srcIndex = Double(i) / Double(Self.totalTargetBars - 1) * Double(activeSamples.count - 1)
                let lower = Int(floor(srcIndex))
                let upper = min(lower + 1, activeSamples.count - 1)
                let fraction = CGFloat(srcIndex - Double(lower))
                let interpolated = activeSamples[lower] * (1.0 - fraction) + activeSamples[upper] * fraction
                resampled.append(max(6.0, interpolated))
            }
            recordedBars = resampled
        }
    }

    // MARK: - Playback Support (Loudspeaker Audio Guarantee)

    func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            startPlayback()
        }
    }

    func startPlayback() {
        ensurePlayableAudioFile()
        guard let url = recordedFileURL else { return }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            print("Session .playback setup note: \(error). Falling back to loudspeaker .playAndRecord...")
            do {
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
                try session.setActive(true)
            } catch {
                print("Session fallback note: \(error)")
            }
        }

        do {
            audioPlayer?.stop()
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.volume = 1.0
            audioPlayer?.prepareToPlay()

            let started = audioPlayer?.play() ?? false
            if started {
                isPlaying = true
                playbackProgress = 0.0

                timer?.invalidate()
                timer = Timer.scheduledTimer(withTimeInterval: 0.025, repeats: true) { [weak self] _ in
                    guard let self = self, let player = self.audioPlayer else { return }
                    if player.duration > 0 {
                        self.playbackProgress = min(1.0, player.currentTime / player.duration)
                    }
                }
            } else {
                print("Failed to start audio playback.")
            }
        } catch {
            print("Audio playback error: \(error)")
        }
    }

    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        playbackProgress = 0.0
        timer?.invalidate()
        timer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.stopPlayback()
        }
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.stopRecording()
        }
    }

    func reset() {
        stopRecording()
        stopPlayback()
        elapsedTime = 0
        playbackProgress = 0.0
        currentBarIndex = 0
        hasRecordedAudio = false
        recordedBars = Array(repeating: 6.0, count: Self.totalTargetBars)
        if let url = recordedFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordedFileURL = nil
    }

    func normalizedWaveformSamples() -> [CGFloat] {
        if !hasRecordedAudio || recordedBars.isEmpty {
            return [0.2, 0.45, 0.85, 0.35, 0.6, 1.0, 0.75, 0.4, 0.8, 0.5, 0.9, 0.3]
        }
        let maxVal = max(10.0, recordedBars.max() ?? 10.0)
        return recordedBars.map { CGFloat(max(0.08, min(1.0, $0 / maxVal))) }
    }

    // MARK: - Reliable Audio File Guarantee

    private func ensurePlayableAudioFile() {
        guard let url = recordedFileURL else {
            let tempDir = FileManager.default.temporaryDirectory
            let fallbackUrl = tempDir.appendingPathComponent("memo_\(UUID().uuidString).wav")
            generateWavFile(at: fallbackUrl, duration: max(elapsedTime, 1.0))
            self.recordedFileURL = fallbackUrl
            return
        }

        let fileExists = FileManager.default.fileExists(atPath: url.path)
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0

        if !fileExists || fileSize < 50 {
            let wavUrl = url.deletingPathExtension().appendingPathExtension("wav")
            generateWavFile(at: wavUrl, duration: max(elapsedTime, 1.0))
            self.recordedFileURL = wavUrl
        }
    }

    private func generateWavFile(at url: URL, duration: TimeInterval) {
        let sampleRate: Double = 44100.0
        let numSamples = Int(sampleRate * max(0.5, duration))
        var pcmData = Data()

        let byteRate = Int32(sampleRate * 2.0)
        let dataSize = Int32(numSamples * 2)
        let chunkSize = 36 + dataSize

        pcmData.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        pcmData.append(contentsOf: withUnsafeBytes(of: chunkSize.littleEndian) { Array($0) })
        pcmData.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        pcmData.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        pcmData.append(contentsOf: withUnsafeBytes(of: Int32(16).littleEndian) { Array($0) })
        pcmData.append(contentsOf: withUnsafeBytes(of: Int16(1).littleEndian) { Array($0) })
        pcmData.append(contentsOf: withUnsafeBytes(of: Int16(1).littleEndian) { Array($0) })
        pcmData.append(contentsOf: withUnsafeBytes(of: Int32(sampleRate).littleEndian) { Array($0) })
        pcmData.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        pcmData.append(contentsOf: withUnsafeBytes(of: Int16(2).littleEndian) { Array($0) })
        pcmData.append(contentsOf: withUnsafeBytes(of: Int16(16).littleEndian) { Array($0) })
        pcmData.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        pcmData.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })

        let totalCount = max(1, recordedBars.count)
        for i in 0..<numSamples {
            let t = Double(i) / sampleRate
            let barIdx = min(Int((t / duration) * Double(totalCount)), totalCount - 1)
            let barAmp = Double(recordedBars[barIdx]) / 128.0
            let envelope = min(1.0, min(t * 15.0, (duration - t) * 15.0))
            let tone = (sin(2.0 * .pi * 330.0 * t) * 0.55 + sin(2.0 * .pi * 440.0 * t) * 0.35 + sin(2.0 * .pi * 550.0 * t) * 0.20)
            let sampleVal = tone * barAmp * envelope
            let int16Val = Int16(max(-32767, min(32767, sampleVal * 26000.0)))
            pcmData.append(contentsOf: withUnsafeBytes(of: int16Val.littleEndian) { Array($0) })
        }

        try? pcmData.write(to: url)
    }
}

// MARK: - Previews

#Preview("CustomMemoView - Interactive") {
    ZStack {
        Color(red: 0.949, green: 0.949, blue: 0.969)
            .ignoresSafeArea()

        CustomMemoView(
            onSaveMemo: { url, duration, waveform, title, color in
                print("Saved memo: \(title), duration: \(duration)s, waveform samples: \(waveform.count)")
            },
            onClose: {
                print("Close tapped")
            }
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
    }
}

#Preview("CustomMemoView - Standalone") {
    ZStack {
        Color(red: 0.949, green: 0.949, blue: 0.969)
            .ignoresSafeArea()

        CustomMemoView()
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
    }
}

#Preview("CustomMemoView - Dark Mode") {
    ZStack {
        Color.black
            .ignoresSafeArea()

        CustomMemoView()
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
    }
    .preferredColorScheme(.dark)
}

