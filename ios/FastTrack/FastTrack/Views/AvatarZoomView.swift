import SwiftUI
import UIKit

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
                    .font(.title).minimumScaleFactor(0.6)
                    .foregroundColor(.white.opacity(0.85))
                    .padding(20)
            }
        }
        .overlay(alignment: .topLeading) {
            if onEdit != nil {
                Button(action: handleEdit) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.title).minimumScaleFactor(0.6)
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
            ZoomableImageView(image: image, onDismiss: onDismiss)
                .accessibilityLabel("Avatar photo")
                .accessibilityHint("Double tap to edit or dismiss")
        } else if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .contentShape(Rectangle())
                        .onTapGesture { onDismiss() }
                        .accessibilityLabel("Avatar photo")
                        .accessibilityHint("Double tap to edit or dismiss")
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

private struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = .clear
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 6
        scrollView.zoomScale = 1
        scrollView.delegate = context.coordinator
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.bouncesZoom = true

        let imageView = context.coordinator.imageView
        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.frame = scrollView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.addSubview(imageView)

        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSingleTap))
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)
        scrollView.addGestureRecognizer(doubleTap)

        context.coordinator.scrollView = scrollView
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.imageView.image = image
        context.coordinator.scrollView = scrollView
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        let imageView = UIImageView()
        private let onDismiss: () -> Void
        weak var scrollView: UIScrollView?

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        @objc
        func handleSingleTap() {
            onDismiss()
        }

        @objc
        func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
                return
            }

            let targetZoom: CGFloat = 3
            let tapPoint = recognizer.location(in: imageView)
            let size = CGSize(
                width: scrollView.bounds.size.width / targetZoom,
                height: scrollView.bounds.size.height / targetZoom
            )
            let rect = CGRect(
                x: tapPoint.x - (size.width / 2),
                y: tapPoint.y - (size.height / 2),
                width: size.width,
                height: size.height
            )
            scrollView.zoom(to: rect, animated: true)
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
