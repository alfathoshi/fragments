//
//  CaptureViewModel.swift
//  fragments
//
//  Created on 9/17/26.
//

import SwiftUI
import UIKit

/// Defines the destination context for a capture session.
public enum CaptureContext: Equatable {
    case personal
    case personalMoment(FolderCollection)
    case room(Room)
}

@Observable
@MainActor
final class CaptureViewModel {
    var selectedMode: CaptureMode
    var activeSession: MomentSession?
    var activeMoment: FolderCollection?
    var captureContext: CaptureContext
    var showLimitAlert: Bool = false
    var limitAlertTitle: String = ""
    var limitAlertMessage: String = ""
    var onCaptureFragment: ((Fragment) -> Void)?
    var onCaptureSharedFragment: ((SharedFragment) -> Void)?

    init(
        initialMode: CaptureMode = .photo,
        activeMoment: FolderCollection? = nil,
        activeSession: MomentSession? = nil,
        captureContext: CaptureContext = .personal,
        onCaptureFragment: ((Fragment) -> Void)? = nil,
        onCaptureSharedFragment: ((SharedFragment) -> Void)? = nil
    ) {
        self.selectedMode = initialMode
        self.activeMoment = activeMoment
        self.activeSession = activeSession
        self.captureContext = captureContext
        self.onCaptureFragment = onCaptureFragment
        self.onCaptureSharedFragment = onCaptureSharedFragment
    }

    func checkCanCapture() -> Bool {
        if case .room(let room) = captureContext {
            if room.backend == .supabase {
                guard SupabaseService.shared.isAuthenticated,
                      UserIdentityService.shared.collaborativeUserID != nil else {
                    limitAlertTitle = "Sign In Required"
                    limitAlertMessage = "You must be signed in with your Supabase account to capture fragments in this collaborative room."
                    showLimitAlert = true
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    return false
                }
            }
            // Collaborative rooms do not apply personal standalone 15-fragment limits
            return true
        }

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

    private func resolveCollaborativeAuthor(for room: Room) -> (authorId: String, authorName: String)? {
        if room.backend == .supabase {
            guard let supabaseUUID = UserIdentityService.shared.collaborativeUserID else {
                limitAlertTitle = "Sign In Required"
                limitAlertMessage = "You must be signed in with your Supabase account to capture fragments in this collaborative room."
                showLimitAlert = true
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                return nil
            }
            return (authorId: supabaseUUID, authorName: ProfileManager.shared.effectiveName)
        } else {
            let legacyId = UserIdentityService.shared.currentUserIdentity?.id ?? "local_user"
            return (authorId: legacyId, authorName: ProfileManager.shared.effectiveName)
        }
    }

    func handlePhotoCapture(image: UIImage?, fileURL: URL?) {
        // TEMPORARY trace (no behavior change).
        print("[PhotoTrace] HANDLE_PHOTO_CAPTURE_START")
        switch captureContext {
        case .room(let room):
            print("[PhotoTrace] captureContext: room id=\(room.id) backend=\(room.backend)")
        case .personalMoment:
            print("[PhotoTrace] captureContext: personalMoment")
        case .personal:
            print("[PhotoTrace] captureContext: personal")
        }
        guard checkCanCapture() else { return }
        let resolvedLocation = LocationManager.shared.currentLocationName ?? "Current Location"

        if case .room(let room) = captureContext {
            guard let author = resolveCollaborativeAuthor(for: room) else { return }
            let coords = Fragment.generateScatteredCoordinates(existing: activeSession?.fragments ?? [])
            let sharedFrag = SharedFragment(
                id: UUID().uuidString,
                roomId: room.id,
                authorId: author.authorId,
                authorName: author.authorName,
                type: .photo,
                createdAt: Date(),
                title: "\(room.name) Photo",
                subtitle: Date().formatted(date: .abbreviated, time: .shortened),
                mediaReference: fileURL != nil ? SharedMediaReference(localFileURL: fileURL, fileExtension: fileURL?.pathExtension) : nil,
                mediaSymbol: "camera.fill",
                location: resolvedLocation,
                phi: coords.phi,
                theta: coords.theta,
                radiusFactor: coords.radiusFactor
            )
            // TEMPORARY trace (no behavior change).
            print("[PhotoTrace] FRAGMENT_CREATED")
            print("[PhotoTrace] fragmentID: \(sharedFrag.id)")
            print("[PhotoTrace] fragmentType: \(sharedFrag.type.rawValue)")
            print("[PhotoTrace] onCaptureSharedFragment present: \(onCaptureSharedFragment != nil)")
            if let onCaptureShared = onCaptureSharedFragment {
                print("[PhotoTrace] ON_CAPTURE_SHARED_FRAGMENT_CALLED")
                onCaptureShared(sharedFrag)
            } else {
                print("[PhotoTrace] ON_CAPTURE_FRAGMENT_FALLBACK")
                onCaptureFragment?(sharedFrag.toFragment())
            }
            Task {
                do {
                    try await RoomManager.shared.captureSharedFragment(sharedFrag)
                } catch {
                    // Never swallow sync failures: on Supabase error the server row
                    // is rolled back, so peers would never receive this capture.
                    print("❌ [Capture] Failed to sync shared fragment \(sharedFrag.id) to room \(room.id): \(error)")
                }
            }
            return
        }

        let mediaPath = fileURL?.path
        let coords = Fragment.generateScatteredCoordinates(existing: activeSession?.fragments ?? [])
        let momentTitle = activeMoment?.name ?? (activeSession != nil ? "Moment" : nil)
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
        let resolvedLocation = LocationManager.shared.currentLocationName ?? "Current Location"

        let filename = "VID_\(UUID().uuidString).mov"
        var savedResourceName = filename
        var finalURL = sourceURL
        if let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let destURL = docsURL.appendingPathComponent(filename)
            if (try? FileManager.default.copyItem(at: sourceURL, to: destURL)) != nil {
                savedResourceName = filename
                finalURL = destURL
            } else {
                savedResourceName = sourceURL.path
            }
        }

        if case .room(let room) = captureContext {
            guard let author = resolveCollaborativeAuthor(for: room) else { return }
            let coords = Fragment.generateScatteredCoordinates(existing: activeSession?.fragments ?? [])
            let sharedFrag = SharedFragment(
                id: UUID().uuidString,
                roomId: room.id,
                authorId: author.authorId,
                authorName: author.authorName,
                type: .video,
                createdAt: Date(),
                title: "\(room.name) Video",
                subtitle: Date().formatted(date: .abbreviated, time: .shortened),
                mediaReference: SharedMediaReference(localFileURL: finalURL, fileExtension: "mov"),
                mediaSymbol: "video.fill",
                location: resolvedLocation,
                duration: formattedDuration,
                phi: coords.phi,
                theta: coords.theta,
                radiusFactor: coords.radiusFactor
            )
            if let onCaptureShared = onCaptureSharedFragment {
                onCaptureShared(sharedFrag)
            } else {
                onCaptureFragment?(sharedFrag.toFragment())
            }
            Task {
                do {
                    try await RoomManager.shared.captureSharedFragment(sharedFrag)
                } catch {
                    // Never swallow sync failures: on Supabase error the server row
                    // is rolled back, so peers would never receive this capture.
                    print("❌ [Capture] Failed to sync shared fragment \(sharedFrag.id) to room \(room.id): \(error)")
                }
            }
            return
        }

        let coords = Fragment.generateScatteredCoordinates(existing: activeSession?.fragments ?? [])
        let momentTitle = activeMoment?.name ?? (activeSession != nil ? "Moment" : nil)
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
        // TEMPORARY trace: working control path for photo comparison.
        print("[PhotoTrace] HANDLE_NOTE_CAPTURE_START (control)")
        guard checkCanCapture() else { return }
        let resolvedLocation = LocationManager.shared.currentLocationName ?? "Current Location"
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        if case .room(let room) = captureContext {
            guard let author = resolveCollaborativeAuthor(for: room) else { return }
            let coords = Fragment.generateScatteredCoordinates(existing: activeSession?.fragments ?? [])
            let finalTitle = trimmedTitle.isEmpty ? "\(room.name) Note" : trimmedTitle
            let sharedFrag = SharedFragment(
                id: UUID().uuidString,
                roomId: room.id,
                authorId: author.authorId,
                authorName: author.authorName,
                type: .note,
                createdAt: Date(),
                title: finalTitle,
                subtitle: Date().formatted(date: .abbreviated, time: .shortened),
                text: text,
                mediaSymbol: "square.and.pencil",
                location: resolvedLocation,
                accentColorHex: color.toRGBAString(),
                phi: coords.phi,
                theta: coords.theta,
                radiusFactor: coords.radiusFactor
            )
            if let onCaptureShared = onCaptureSharedFragment {
                onCaptureShared(sharedFrag)
            } else {
                onCaptureFragment?(sharedFrag.toFragment())
            }
            Task {
                do {
                    try await RoomManager.shared.captureSharedFragment(sharedFrag)
                } catch {
                    // Never swallow sync failures: on Supabase error the server row
                    // is rolled back, so peers would never receive this capture.
                    print("❌ [Capture] Failed to sync shared fragment \(sharedFrag.id) to room \(room.id): \(error)")
                }
            }
            return
        }

        let coords = Fragment.generateScatteredCoordinates(existing: activeSession?.fragments ?? [])
        let momentTitle = activeMoment?.name ?? (activeSession != nil ? "Moment" : nil)
        let resolvedTitle = trimmedTitle.isEmpty
            ? (momentTitle != nil ? "\(momentTitle!) Note" : "Memo Fragment")
            : trimmedTitle

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
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        let formattedDuration = String(format: "%d:%02d", mins, secs)
        let resolvedLocation = LocationManager.shared.currentLocationName ?? "Current Location"
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        if case .room(let room) = captureContext {
            guard let author = resolveCollaborativeAuthor(for: room) else { return }
            let coords = Fragment.generateScatteredCoordinates(existing: activeSession?.fragments ?? [])
            let finalTitle = trimmedTitle.isEmpty ? "\(room.name) Voice Memo" : trimmedTitle
            let sharedFrag = SharedFragment(
                id: UUID().uuidString,
                roomId: room.id,
                authorId: author.authorId,
                authorName: author.authorName,
                type: .audio,
                createdAt: Date(),
                title: finalTitle,
                subtitle: Date().formatted(date: .abbreviated, time: .shortened),
                mediaReference: fileURL != nil ? SharedMediaReference(localFileURL: fileURL, fileExtension: fileURL?.pathExtension) : nil,
                mediaSymbol: "waveform",
                location: resolvedLocation,
                duration: formattedDuration,
                audioWaveform: waveform,
                accentColorHex: color.toRGBAString(),
                phi: coords.phi,
                theta: coords.theta,
                radiusFactor: coords.radiusFactor
            )
            if let onCaptureShared = onCaptureSharedFragment {
                onCaptureShared(sharedFrag)
            } else {
                onCaptureFragment?(sharedFrag.toFragment())
            }
            Task {
                do {
                    try await RoomManager.shared.captureSharedFragment(sharedFrag)
                } catch {
                    // Never swallow sync failures: on Supabase error the server row
                    // is rolled back, so peers would never receive this capture.
                    print("❌ [Capture] Failed to sync shared fragment \(sharedFrag.id) to room \(room.id): \(error)")
                }
            }
            return
        }

        let coords = Fragment.generateScatteredCoordinates(existing: activeSession?.fragments ?? [])
        let momentTitle = activeMoment?.name ?? (activeSession != nil ? "Moment" : nil)
        let resolvedTitle = trimmedTitle.isEmpty
            ? (momentTitle != nil ? "\(momentTitle!) Memo" : "Voice Memo")
            : trimmedTitle

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
