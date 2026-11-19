import CloudKit
import SwiftUI
import UIKit

struct CloudShareSheet: UIViewControllerRepresentable {
    let share: CKShare
    let containerID: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: CKContainer(identifier: containerID))
        controller.availablePermissions = [.allowReadWrite]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            Task { @MainActor in
                AppRuntime.model?.lastError = CloudKitErrorText.message(for: error)
            }
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            "Wakito"
        }
    }
}
