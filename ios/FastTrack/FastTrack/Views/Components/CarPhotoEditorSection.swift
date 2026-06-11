import SwiftUI
import PhotosUI
import UIKit

// MARK: - CarPhotoEditorSection
//
// A reusable form row that manages picking, cropping, and removing a car
// photo. Used by both `AddCarView` and `EditCarView`.
//
// The caller owns:
//   • `pickedImage` — the final cropped UIImage (nil = no new photo)
//   • `existingPhotoURL` — a URL string shown when `pickedImage` is nil
//   • `isUploading` / `errorMessage` — passed through from the parent
//   • `onRemove` — called when the user taps "Remove Photo"
//
// Full-screen crop is handled internally via a `.fullScreenCover` on
// `croppingImage`. The parent's own `.onChange(of: pickedPhoto)` in the
// original views is replaced by the internal `.onChange` here.

struct CarPhotoEditorSection: View {
    @Binding var pickedImage: UIImage?
    let existingPhotoURL: String?
    var isUploading: Bool = false
    var errorMessage: String? = nil
    var onRemove: () -> Void

    @State private var pickedPhoto: PhotosPickerItem?
    @State private var croppingImage: CropImageSource?

    var body: some View {
        HStack(spacing: 12) {
            photoPreview
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))

            VStack(alignment: .leading, spacing: 6) {
                PhotosPicker(selection: $pickedPhoto, matching: .images) {
                    Text(photoButtonTitle)
                }
                .disabled(isUploading)

                if hasPhoto {
                    Button(role: .destructive) {
                        onRemove()
                        pickedPhoto = nil
                    } label: {
                        Text("Remove Photo")
                    }
                    .disabled(isUploading)
                }

                if isUploading {
                    ProgressView()
                        .controlSize(.small)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .onChange(of: pickedPhoto) { _, item in
            Task { await loadPickedPhoto(item) }
        }
        .fullScreenCover(item: $croppingImage, onDismiss: {
            pickedPhoto = nil
        }) { source in
            PhotoCropView(image: source.image, context: source.context) { cropped in
                pickedImage = cropped.resizedForAvatar(maxDimension: 800)
            }
        }
    }

    // MARK: - Photo preview

    @ViewBuilder
    private var photoPreview: some View {
        if let pickedImage {
            Image(uiImage: pickedImage)
                .resizable()
                .scaledToFill()
        } else if let url = existingPhotoURL, !url.isEmpty,
                  let photoURL = URL(string: url) {
            AsyncImage(url: photoURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    carIconPlaceholder
                }
            }
        } else {
            carIconPlaceholder
        }
    }

    private var carIconPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.sm)
                .fill(Color.ftBlue.opacity(0.15))
            Image(systemName: "car.fill")
                .foregroundColor(.blue)
        }
    }

    // MARK: - Helpers

    private var hasPhoto: Bool {
        pickedImage != nil || (existingPhotoURL != nil && !(existingPhotoURL!.isEmpty))
    }

    private var photoButtonTitle: String {
        pickedImage != nil ? "Change Photo" :
            (existingPhotoURL.map { !$0.isEmpty } == true ? "Change Photo" : "Set Photo")
    }

    @MainActor
    private func loadPickedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let img = UIImage(data: data) else {
                return
            }
            let resized = img.resizedForAvatar(maxDimension: 2048)
            croppingImage = CropImageSource(image: resized, context: .car)
        } catch {
            // Error surfaced to parent via errorMessage binding if needed.
        }
    }
}
