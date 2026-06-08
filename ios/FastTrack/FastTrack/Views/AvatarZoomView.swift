import SwiftUI
import UIKit

// MARK: - Avatar zoom
//
// A minimal fullscreen overlay that loads an avatar (or any other) image
// at its native size and dismisses on tap. Pinch-to-zoom is intentionally
// out of scope for the first pass — the redesign calls it "nice to have".
//
// At most one of `url` / `image` is expected to be set; if both are nil we
// fall back to a generic person-icon placeholder.
//
// `onEdit`, when non-nil, surfaces a top-leading "Edit" button. Tapping it
// hands a `UIImage` to the parent (fetched from `url` if needed) so the
// parent can drive the cropper / re-save flow. The zoom itself is
// presentation-only and never owns the cropper state.
struct AvatarZoomView: View {
    let url: URL?
    var image: UIImage? = nil
    let onDismiss: () -> Void
    var onEdit: ((UIImage) -> Void)? = nil

    @State private var isFetchingEditImage = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(20)
            }
        }
        .overlay(alignment: .topLeading) {
            if onEdit != nil {
                Button(action: handleEdit) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(20)
                }
                .disabled(isFetchingEditImage)
                .accessibilityLabel("Edit avatar")
                .accessibilityHint("Opens the cropper to adjust your avatar")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }
        } else if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .contentShape(Rectangle())
                        .onTapGesture { onDismiss() }
                default:
                    ProgressView()
                        .tint(.white)
                }
            }
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 200)
                .foregroundColor(.white.opacity(0.6))
        }
    }

    /// Forwards a UIImage to the parent's `onEdit` closure. Uses the
    /// in-memory `image` when available, otherwise fetches the bytes
    /// behind `url` (e.g. for a server-hosted avatar the user wants to
    /// re-crop). The parent decides what to do with the image — typically
    /// present `PhotoCropView` and re-save via `ProfileManager.saveAvatar`.
    private func handleEdit() {
        guard let onEdit else { return }
        if let image {
            onEdit(image)
            return
        }
        guard let url else { return }
        isFetchingEditImage = true
        Task.detached {
            let fetched: UIImage? = await {
                guard let (data, _) = try? await URLSession.shared.data(from: url) else {
                    return nil
                }
                return UIImage(data: data)
            }()
            await MainActor.run {
                isFetchingEditImage = false
                if let fetched {
                    onEdit(fetched)
                }
            }
        }
    }
}

/// Identifiable wrapper so `.fullScreenCover(item:)` can present an
/// AvatarZoomView bound to an optional URL or local image. The `id` is
/// derived from whichever source is set so presenting the same avatar
/// twice is treated as one item.
struct AvatarZoomTarget: Identifiable, Equatable {
    let url: URL?
    let image: UIImage?

    init(url: URL?) {
        self.url = url
        self.image = nil
    }

    init(image: UIImage?) {
        self.url = nil
        self.image = image
    }

    var id: String {
        if let url { return url.absoluteString }
        return "memory"
    }
}
