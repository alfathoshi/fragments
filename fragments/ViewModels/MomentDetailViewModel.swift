//
//  MomentDetailViewModel.swift
//  fragments
//
//  Created on 9/17/26.
//

import SwiftUI
import AVFoundation

@Observable
@MainActor
final class MomentDetailViewModel {
    let collection: FolderCollection
    var onUpdateCollection: ((FolderCollection) -> Void)?

    // Ordered items representing discrete spots (Home Screen style)
    var items: [FolderItem] = []
    var originalItems: [FolderItem] = []
    var isSavedConfirmation: Bool = false

    // Check whether items order has changed compared to saved layout
    var hasReordered: Bool {
        guard items.count == originalItems.count else { return false }
        return items.map(\.id) != originalItems.map(\.id)
    }

    // Drag-to-reorder state (Tap & Hold to Move)
    var draggedItemID: UUID? = nil
    var dragCurrentIndex: Int? = nil
    var dragInitialCenter: CGPoint = .zero
    var dragLiveTranslation: CGSize = .zero
    var lastReorderTime: Date = .distantPast

    // Audio playback state (Voice memo)
    var currentlyPlayingAudioID: UUID? = nil
    var audioPlayer: AVAudioPlayer? = nil
    var playbackTimer: Timer? = nil
    var audioProgress: [UUID: Double] = [:]

    // Video audio playback state
    var unmutedVideoID: UUID? = nil

    // MARK: - Date Formatters

    static let timeOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    static let dayMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    static let dayMonthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    init(
        collection: FolderCollection,
        onUpdateCollection: ((FolderCollection) -> Void)? = nil
    ) {
        self.collection = collection
        self.onUpdateCollection = onUpdateCollection
    }

    // MARK: - Discrete Spot Geometry Calculation
    func spotFrame(for index: Int, cardWidth: CGFloat, cardHeight: CGFloat, gutter: CGFloat) -> CGRect {
        let col = index % 2
        let row = index / 2
        let topOffset: CGFloat = 16.0
        let x = CGFloat(col) * (cardWidth + gutter)
        let y = topOffset + CGFloat(row) * (cardHeight + gutter)
        return CGRect(x: x, y: y, width: cardWidth, height: cardHeight)
    }

    func initializeItems() {
        if let currentCollection = MomentManager.shared.collections.first(where: { $0.id == collection.id }) {
            items = currentCollection.items
            originalItems = currentCollection.items
        } else {
            items = collection.items
            originalItems = collection.items
        }
    }

    func saveCurrentLayout() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        var updated = collection
        updated.items = items
        originalItems = items

        onUpdateCollection?(updated)
        MomentManager.shared.updateMomentItems(id: collection.id, items: items)

        withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
            isSavedConfirmation = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeInOut(duration: 0.25)) {
                self.isSavedConfirmation = false
            }
        }
    }

    func handleDisplacement(
        cardCenter: CGPoint,
        cardWidth: CGFloat,
        cardHeight: CGFloat,
        gutter: CGFloat,
        horizontalMargin: CGFloat
    ) {
        guard let currentIndex = dragCurrentIndex, items.indices.contains(currentIndex) else { return }

        // Find the spot that is closest to cardCenter
        var bestIndex = currentIndex
        var minDistance = CGFloat.greatestFiniteMagnitude

        for i in 0..<items.count {
            let spot = spotFrame(for: i, cardWidth: cardWidth, cardHeight: cardHeight, gutter: gutter)
            let spotCenter = CGPoint(x: horizontalMargin + spot.midX, y: spot.midY)
            let dist = hypot(cardCenter.x - spotCenter.x, cardCenter.y - spotCenter.y)
            if dist < minDistance {
                minDistance = dist
                bestIndex = i
            }
        }

        // Hysteresis & cooldown check: Must be within 60% of card width
        // AND have a 280ms cooldown to completely eliminate back-and-forth oscillation
        if bestIndex != currentIndex && minDistance < (cardWidth * 0.60) {
            let now = Date()
            if now.timeIntervalSince(lastReorderTime) > 0.28 {
                lastReorderTime = now
                withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                    let moved = items.remove(at: currentIndex)
                    items.insert(moved, at: bestIndex)
                    dragCurrentIndex = bestIndex
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }

    func endDragSnap(
        cardWidth: CGFloat,
        cardHeight: CGFloat,
        gutter: CGFloat,
        horizontalMargin: CGFloat
    ) {
        guard let currentIndex = dragCurrentIndex, items.indices.contains(currentIndex) else {
            draggedItemID = nil
            dragCurrentIndex = nil
            dragLiveTranslation = .zero
            return
        }

        let targetSpot = spotFrame(for: currentIndex, cardWidth: cardWidth, cardHeight: cardHeight, gutter: gutter)
        let targetCenter = CGPoint(x: horizontalMargin + targetSpot.midX, y: targetSpot.midY)

        let visualCenter = CGPoint(
            x: dragInitialCenter.x + dragLiveTranslation.width,
            y: dragInitialCenter.y + dragLiveTranslation.height
        )

        // Seamless re-anchoring: preserve exact visual coordinate
        dragInitialCenter = targetCenter
        dragLiveTranslation = CGSize(
            width: visualCenter.x - targetCenter.x,
            height: visualCenter.y - targetCenter.y
        )

        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            dragLiveTranslation = .zero
        } completion: {
            self.draggedItemID = nil
            self.dragCurrentIndex = nil
            self.dragLiveTranslation = .zero
        }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Formats the widget subtitle based on the fragment timestamp vs the moment date.
    /// Returns only the time if captured on the same calendar day; otherwise includes date and time.
    func formattedSubtitle(for item: FolderItem) -> String {
        let date = resolveItemDate(for: item)
        let timeString = Self.timeOnlyFormatter.string(from: date)

        if Calendar.current.isDate(date, inSameDayAs: collection.date) {
            return timeString
        } else {
            let isSameYear = Calendar.current.isDate(date, equalTo: collection.date, toGranularity: .year)
            let dateString = isSameYear
                ? Self.dayMonthFormatter.string(from: date)
                : Self.dayMonthYearFormatter.string(from: date)
            return "\(dateString), \(timeString)"
        }
    }

    func resolveItemDate(for item: FolderItem) -> Date {
        if let createdAt = item.createdAt {
            return createdAt
        }

        guard let sub = item.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !sub.isEmpty else {
            return collection.date
        }

        let calendar = Calendar.current

        // Check if subtitle is a pure time string (e.g., "2.30 PM", "2:30 PM", "14:30")
        let timeFormats = ["h.mm a", "h:mm a", "h a", "HH:mm", "H:mm"]
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        for fmt in timeFormats {
            timeFormatter.dateFormat = fmt
            if let parsedTime = timeFormatter.date(from: sub) {
                let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: parsedTime)
                if let combined = calendar.date(bySettingHour: timeComponents.hour ?? 0,
                                                minute: timeComponents.minute ?? 0,
                                                second: timeComponents.second ?? 0,
                                                of: collection.date) {
                    return combined
                }
            }
        }

        // Check full date & time formats
        let fullFormats = [
            "MMM d, yyyy 'at' h:mm a",
            "MMM d, yyyy, h:mm a",
            "MMM d, yyyy h:mm a",
            "MMM d, h:mm a",
            "MMM d 'at' h:mm a",
            "yyyy-MM-dd'T'HH:mm:ssZ"
        ]
        for fmt in fullFormats {
            timeFormatter.dateFormat = fmt
            if let parsedDate = timeFormatter.date(from: sub) {
                if !fmt.contains("yyyy") {
                    let year = calendar.component(.year, from: collection.date)
                    var comps = calendar.dateComponents([.month, .day, .hour, .minute], from: parsedDate)
                    comps.year = year
                    if let withYear = calendar.date(from: comps) {
                        return withYear
                    }
                }
                return parsedDate
            }
        }

        let systemFormatter = DateFormatter()
        systemFormatter.dateStyle = .medium
        systemFormatter.timeStyle = .short
        if let parsed = systemFormatter.date(from: sub) {
            return parsed
        }

        return collection.date
    }

    // MARK: - Audio Coordination (Voice Memo & Video Sound)
    func toggleAudio(for item: FolderItem) {
        if currentlyPlayingAudioID == item.id {
            stopAudio()
        } else {
            // Mute any video audio
            unmutedVideoID = nil
            stopAudio()
            playAudio(for: item)
        }
    }

    func toggleVideoAudio(for item: FolderItem) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if unmutedVideoID == item.id {
            unmutedVideoID = nil
        } else {
            // Stop any playing voice memo
            stopAudio()
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .default)
            try? session.setActive(true)
            unmutedVideoID = item.id
        }
    }

    func playAudio(for item: FolderItem) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        currentlyPlayingAudioID = item.id
        audioProgress[item.id] = 0.0

        if let url = item.toFragment().mediaURL {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .default)
            try? session.setActive(true)

            if let player = try? AVAudioPlayer(contentsOf: url) {
                self.audioPlayer = player
                player.play()
            }
        }

        let totalDuration: Double = {
            if let durStr = item.duration {
                let parts = durStr.split(separator: ":")
                if parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1]) {
                    return max(1.0, m * 60.0 + s)
                } else if let val = Double(durStr) {
                    return max(1.0, val)
                }
            }
            return 4.0
        }()

        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            if let player = self.audioPlayer, player.duration > 0 {
                let currentProg = player.currentTime / player.duration
                self.audioProgress[item.id] = currentProg
                if !player.isPlaying {
                    self.stopAudio()
                }
            } else {
                let current = (self.audioProgress[item.id] ?? 0.0) + (0.05 / totalDuration)
                if current >= 1.0 {
                    self.stopAudio()
                } else {
                    self.audioProgress[item.id] = current
                }
            }
        }
    }

    func stopAudio() {
        audioPlayer?.stop()
        audioPlayer = nil
        playbackTimer?.invalidate()
        playbackTimer = nil
        if let id = currentlyPlayingAudioID {
            audioProgress[id] = 0.0
        }
        currentlyPlayingAudioID = nil
    }
}
