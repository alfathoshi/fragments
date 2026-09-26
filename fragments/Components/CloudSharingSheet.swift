//
//  CloudSharingSheet.swift
//  fragments
//
//  Created on 9/25/26.
//

import SwiftUI
import UIKit
import CloudKit

/// SwiftUI wrapper around Apple's native `UICloudSharingController`.
/// Presents the system sharing flow for inviting members to a private Room via Messages, Mail, AirDrop, etc.
public struct CloudSharingSheet: UIViewControllerRepresentable {
    public let share: CKShare
    public let container: CKContainer?
    public var onDismiss: (() -> Void)?

    public init(
        share: CKShare,
        container: CKContainer? = CloudKitService.shared.container,
        onDismiss: (() -> Void)? = nil
    ) {
        self.share = share
        self.container = container
        self.onDismiss = onDismiss
    }

    public func makeUIViewController(context: Context) -> UIViewController {
        guard let container, share.url != nil else {
            let alert = UIAlertController(
                title: "iCloud Link Unavailable",
                message: "iCloud sharing requires an active Apple Account signed in via iOS Settings. If testing on a simulator, use 'Copy Invite Link' or 'Share Link via...' to connect devices.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                self.onDismiss?()
            })
            return alert
        }
        let controller = UICloudSharingController(share: share, container: container)
        controller.delegate = context.coordinator
        controller.availablePermissions = [.allowReadWrite, .allowReadOnly, .allowPrivate]
        return controller
    }

    public func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        private let parent: CloudSharingSheet

        public init(_ parent: CloudSharingSheet) {
            self.parent = parent
        }

        public func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {}

        public func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            parent.onDismiss?()
        }

        public func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {}

        public func itemTitle(for csc: UICloudSharingController) -> String? {
            parent.share[CKShare.SystemFieldKey.title] as? String
        }
    }
}
