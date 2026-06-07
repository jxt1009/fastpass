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
struct AvatarZoomView: View {
    let url: URL?
    var image: UIImage? = nil
    let onDismiss: () -> Void

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
