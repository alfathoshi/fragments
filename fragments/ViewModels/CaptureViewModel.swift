//
//  CaptureViewModel.swift
//  fragments
//
//  Created on 9/17/26.
//

import SwiftUI
import UIKit

@Observable
@MainActor
final class CaptureViewModel {
    var selectedMode: CaptureMode
    var activeSession: MomentSession?
    var activeMoment: FolderCollection?
    var showLimitAlert: Bool = false
    var limitAlertTitle: String = ""
    var limitAlertMessage: String = ""
    var onCaptureFragment: ((Fragment) -> Void)?

    init(
        initialMode: CaptureMode = .photo,
        activeMoment: FolderCollection? = nil,
        activeSession: MomentSession? = nil,
        onCaptureFragment: ((Fragment) -> Void)? = nil
    ) {
        self.selectedMode = initialMode
        self.activeMoment = activeMoment
        self.activeSession = activeSession
        self.onCaptureFragment = onCaptureFragment
    }

    func checkCanCapture() -> Bool {
        if let session = activeSession {
            if session.fragments.count >= MomentSession.maxFragments {
                limitAlertTitle = "Moment Limit Reached"
                limitAlertMessage = "A moment can contain a maximum of 15 fragments."
                showLimitAlert = true
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                return false
            }
        } else {
            MomentManager.shared.cleanupExpiredStandaloneFragments()
            if MomentManager.shared.standaloneFragments.count >= MomentManager.maxStandaloneFragments {
                limitAlertTitle = "Fragment Limit Reached"
                limitAlertMessage = "You can only capture up to 15 fragments. Standalone fragments disappear after 24 hours, or you can delete some to capture more."
                showLimitAlert = true
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                return false
            }
        }
        return true
    }

    func handlePhotoCapture(image: UIImage?, fileURL: URL?) {
        guard checkCanCapture() else { return }
        let mediaPath = fileURL?.path
        let coords = Fragment.generateScatteredCoordinates(existing: activeSession?.fragments ?? [])
        let momentTitle = activeMoment?.name ?? (activeSession != nil ? "Moment" : nil)
        let resolvedLocation = LocationManager.shared.currentLocationName ?? "Current Location"
        let fragment = Fragment(
            type: .photo,
            title: momentTitle != nil ? "\(momentTitle!) Photo" : "Photo Fragment",
            subtitle: Date().formatted(date: .abbreviated, time: .shortened),
            mediaResourceName: mediaPath,
            gradientColors: [Color(red: 1.0, green: 0.55, blue: 0.35), Color(red: 0.95, green: 0.25, blue: 0.55)],
            location: resolvedLocation,
            phi: coords.phi,
            theta: coords.theta,
            radiusFactor: coords.radiusFactor
        )
        onCaptureFragment?(fragment)
    }

    func handleVideoCapture(url: URL?, duration: TimeInterval) {
        guard checkCanCapture() else { return }
        guard let sourceURL = url else { return }
        let formattedDuration = String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60)
        
        let filename = "VID_\(UUID().uuidString).mov"
        var savedResourceName = filename
        if let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let destURL = docsURL.appendingPathComponent(filename)
            if (try? FileManager.default.copyItem(at: sourceURL, to: destURL)) != nil {
                savedResourceName = filename
            } else {
                savedResourceName = sourceURL.path
            }
        }
        
        let coords = Fragment.generateScatteredCoordinates(existing: activeSession?.fragments ?? [])
        let momentTitle = activeMoment?.name ?? (activeSession != nil ? "Moment" : nil)
        let resolvedLocation = LocationManager.shared.currentLocationName ?? "Current Location"
        let fragment = Fragment(
            type: .video,
            title: momentTitle != nil ? "\(momentTitle!) Video" : "Video Fragment",
            subtitle: Date().formatted(date: .abbreviated, time: .shortened),
            mediaResourceName: savedResourceName,
            gradientColors: [Color(red: 0.35, green: 0.65, blue: 1.0), Color(red: 0.20, green: 0.45, blue: 0.95)],
            location: resolvedLocation,
            duration: formattedDuration,
            phi: coords.phi,
            theta: coords.theta,
            radiusFactor: coords.radiusFactor
        )
        onCaptureFragment?(fragment)
    }

    func handleNoteCapture(title: String, text: String, color: Color) {
        guard checkCanCapture() else { return }
        let coords = Fragment.generateScatteredCoordinates(existing: activeSession?.fragments ?? [])
        let momentTitle = activeMoment?.name ?? (activeSession != nil ? "Moment" : nil)
        let resolvedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (momentTitle != nil ? "\(momentTitle!) Note" : "Memo Fragment")
            : title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedLocation = LocationManager.shared.currentLocationName ?? "Current Location"

        let fragment = Fragment(
            type: .note,
            title: resolvedTitle,
            subtitle: Date().formatted(date: .abbreviated, time: .shortened),
            text: text,
            gradientColors: [color, color.opacity(0.85)],
            location: resolvedLocation,
            phi: coords.phi,
            theta: coords.theta,
            radiusFactor: coords.radiusFactor
        )
        onCaptureFragment?(fragment)
    }

    func handleMemoCapture(fileURL: URL?, duration: TimeInterval, waveform: [CGFloat], title: String, color: Color) {
        guard checkCanCapture() else { return }
        let coords = Fragment.generateScatteredCoordinates(existing: activeSession?.fragments ?? [])
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        let formattedDuration = String(format: "%d:%02d", mins, secs)

        let momentTitle = activeMoment?.name ?? (activeSession != nil ? "Moment" : nil)
        let resolvedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (momentTitle != nil ? "\(momentTitle!) Memo" : "Voice Memo")
            : title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedLocation = LocationManager.shared.currentLocationName ?? "Current Location"

        let fragment = Fragment(
            type: .audio,
            title: resolvedTitle,
            subtitle: Date().formatted(date: .abbreviated, time: .shortened),
            mediaResourceName: fileURL?.path,
            gradientColors: [color, color.opacity(0.80)],
            location: resolvedLocation,
            duration: formattedDuration,
            audioWaveform: waveform,
            phi: coords.phi,
            theta: coords.theta,
            radiusFactor: coords.radiusFactor
        )
        onCaptureFragment?(fragment)
    }
}
