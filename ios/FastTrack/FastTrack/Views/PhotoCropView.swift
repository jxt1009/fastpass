import SwiftUI
import UIKit

struct PhotoCropView: View {
    let image: UIImage
    let onConfirm: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var savedScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var savedOffset: CGSize = .zero

    private let cropSize: CGFloat = 320
    private let minScale: CGFloat = 1
    private let maxScale: CGFloat = 4

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                cropContent
                dimmedOverlay
                cropBorder
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(combinedGesture)
            .navigationTitle("Crop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Use") {
                        onConfirm(renderCropped())
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var cropContent: some View {
        ZStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .scaleEffect(scale)
                .offset(offset)
        }
        .frame(width: cropSize, height: cropSize)
        .clipped()
    }

    private var dimmedOverlay: some View {
        Color.black.opacity(0.5)
            .mask {
                ZStack {
                    Rectangle()
                    Rectangle()
                        .frame(width: cropSize, height: cropSize)
                        .blendMode(.destinationOut)
                }
            }
            .allowsHitTesting(false)
    }

    private var cropBorder: some View {
        Rectangle()
            .strokeBorder(Color.white, lineWidth: 2)
            .frame(width: cropSize, height: cropSize)
            .allowsHitTesting(false)
    }

    private var combinedGesture: some Gesture {
        SimultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    let next = savedScale * value
                    scale = min(max(next, minScale), maxScale)
                }
                .onEnded { _ in
                    savedScale = scale
                },
            DragGesture()
                .onChanged { value in
                    let bound = maxOffset
                    offset = CGSize(
                        width: clamp(savedOffset.width + value.translation.width, limit: bound.width),
                        height: clamp(savedOffset.height + value.translation.height, limit: bound.height)
                    )
                }
                .onEnded { _ in
                    savedOffset = offset
                }
        )
    }

    private func clamp(_ value: CGFloat, limit: CGFloat) -> CGFloat {
        min(max(value, -limit), limit)
    }

    private var maxOffset: CGSize {
        let imgSize = image.size
        guard imgSize.width > 0, imgSize.height > 0 else { return .zero }
        let baseScale = max(cropSize / imgSize.width, cropSize / imgSize.height)
        let displayW = imgSize.width * baseScale * scale
        let displayH = imgSize.height * baseScale * scale
        return CGSize(
            width: max(0, (displayW - cropSize) / 2),
            height: max(0, (displayH - cropSize) / 2)
        )
    }

    @MainActor
    private func renderCropped() -> UIImage {
        let renderer = ImageRenderer(content: cropContent)
        renderer.scale = UIScreen.main.scale
        renderer.proposedSize = ProposedViewSize(width: cropSize, height: cropSize)
        return renderer.uiImage ?? image
    }
}

struct CropImageSource: Identifiable {
    let id = UUID()
    let image: UIImage
}
