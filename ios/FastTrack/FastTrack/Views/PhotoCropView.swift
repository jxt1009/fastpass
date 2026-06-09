import SwiftUI
import UIKit
import CropViewController

struct PhotoCropView: View {
    let image: UIImage
    let context: PhotoCropContext
    let onConfirm: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PhotoCropController(
            image: image,
            context: context,
            onConfirm: { cropped in
                onConfirm(cropped)
                dismiss()
            },
            onCancel: {
                dismiss()
            }
        )
        .ignoresSafeArea()
    }
}

private struct PhotoCropController: UIViewControllerRepresentable {
    let image: UIImage
    let context: PhotoCropContext
    let onConfirm: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onConfirm: onConfirm, onCancel: onCancel)
    }

    func makeUIViewController(context coordinatorContext: Context) -> CropViewController {
        let controller = CropViewController(image: image)
        controller.delegate = coordinatorContext.coordinator
        controller.title = self.context.navigationTitle
        controller.aspectRatioPreset = CGSize(width: self.context.aspectRatio, height: self.context.aspectRatio)
        controller.aspectRatioLockEnabled = self.context.locksAspectRatio
        controller.resetAspectRatioEnabled = false
        controller.rotateButtonsHidden = true
        controller.rotateClockwiseButtonHidden = true
        controller.doneButtonTitle = "Use"
        controller.cancelButtonTitle = "Cancel"
        return controller
    }

    func updateUIViewController(_ uiViewController: CropViewController, context: Context) {}

    final class Coordinator: NSObject, CropViewControllerDelegate {
        private let onConfirm: (UIImage) -> Void
        private let onCancel: () -> Void

        init(onConfirm: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onConfirm = onConfirm
            self.onCancel = onCancel
        }

        func cropViewController(
            _ cropViewController: CropViewController,
            didCropToImage image: UIImage,
            withRect cropRect: CGRect,
            angle: Int
        ) {
            onConfirm(image)
        }

        func cropViewController(_ cropViewController: CropViewController, didFinishCancelled cancelled: Bool) {
            onCancel()
        }
    }
}

struct CropImageSource: Identifiable {
    let id = UUID()
    let image: UIImage
    let context: PhotoCropContext
}
