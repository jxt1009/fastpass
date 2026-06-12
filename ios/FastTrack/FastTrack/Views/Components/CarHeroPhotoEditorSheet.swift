import SwiftUI
import PhotosUI
import UIKit
import os.log

// MARK: - CarHeroPhotoEditorSheet
//
// Sheet variant of the car photo editor for the hero photo in
// `CarDetailView`. Differs from `CarPhotoEditorSection` in two ways:
//
//   1. It can offer the current photo as a crop source — useful when
//      the user wants to re-crop an existing photo they don't have on
//      their device anymore.
//   2. It commits the upload immediately on confirm (no separate Save
//      step) because the parent only opens this sheet for the photo.
//
// The download path uses `URLSession.shared.data(from:)` against the
// server-relative `existingPhotoURL`. The loader is exposed as a static
// so tests can stub the network response via `URLProtocol`.

struct CarHeroPhotoEditorSheet: View {
    let carId: String
    let existingPhotoURL: String?
    var onUploadComplete: (URL) -> Void

    @EnvironmentObject var apiService: APIService
    @Environment(\.dismiss) private var dismiss

    @State private var pickedPhoto: PhotosPickerItem?
    @State private var sourceImage: UIImage?
    @State private var croppingImage: CropImageSource?
    @State private var isLoading: Bool = false
    @State private var isUploading: Bool = false
    @State private var errorMessage: String?
    @State private var downloadTask: Task<Void, Never>?

    private static let log = Logger(subsystem: "com.fasttrack.app", category: "CarHeroPhotoEditor")

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                heroPreview
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

                actionArea

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Edit Car Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isUploading)
                }
            }
            .onAppear { startDownloadIfNeeded() }
            .onDisappear { downloadTask?.cancel() }
            .onChange(of: pickedPhoto) { _, item in
                Task { await loadPickedPhoto(item) }
            }
            .fullScreenCover(item: $croppingImage, onDismiss: clearCropping) { source in
                PhotoCropView(image: source.image, context: source.context) { cropped in
                    Task { await upload(cropped) }
                }
            }
        }
    }

    @ViewBuilder
    private var actionArea: some View {
        if let sourceImage {
            Button {
                croppingImage = CropImageSource(image: sourceImage, context: .car)
            } label: {
                Text("Use Existing Photo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isUploading)

            PhotosPicker(selection: $pickedPhoto, matching: .images) {
                Text("Choose Different Photo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isUploading)
        } else if hasExistingPhoto {
            PhotosPicker(selection: $pickedPhoto, matching: .images) {
                Text("Choose Photo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading || isUploading)

            if !isLoading {
                Text("Couldn't load existing photo")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            PhotosPicker(selection: $pickedPhoto, matching: .images) {
                Text("Choose Photo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isUploading)
        }
    }

    @ViewBuilder
    private var heroPreview: some View {
        if let sourceImage {
            Image(uiImage: sourceImage)
                .resizable()
                .scaledToFill()
        } else if isLoading {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(Color.secondary.opacity(0.15))
                ProgressView()
            }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(Color.secondary.opacity(0.15))
                Image(systemName: "car.fill")
                    .font(FTFont.iconXLarge).minimumScaleFactor(0.6)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var hasExistingPhoto: Bool {
        guard let url = existingPhotoURL, !url.isEmpty else { return false }
        return URL(string: url) != nil
    }

    // MARK: - Download

    private func startDownloadIfNeeded() {
        guard hasExistingPhoto, !isLoading, sourceImage == nil else { return }
        guard let url = URL(string: existingPhotoURL ?? "") else { return }
        isLoading = true
        downloadTask = Task {
            do {
                let image = try await Self.loadImage(from: url)
                if Task.isCancelled { return }
                sourceImage = image
                croppingImage = CropImageSource(image: image, context: .car)
            } catch {
                Self.log.error("Failed to download existing car photo: \(error.localizedDescription)")
            }
            if !Task.isCancelled { isLoading = false }
        }
    }

    /// Fetches a `UIImage` from `url`. Exposed as a static seam so
    /// tests can target the same call site as production code.
    static func loadImage(from url: URL, session: URLSession = .shared) async throws -> UIImage {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(
                domain: "CarHeroPhotoEditorSheet",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Response was not an HTTP response"]
            )
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NSError(
                domain: "CarHeroPhotoEditorSheet",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Server returned HTTP \(http.statusCode)"]
            )
        }
        guard let image = UIImage(data: data) else {
            throw NSError(
                domain: "CarHeroPhotoEditorSheet",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Downloaded data was not a valid image"]
            )
        }
        return image
    }

    // MARK: - Picker

    @MainActor
    private func loadPickedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let img = UIImage(data: data) else { return }
            let resized = img.resizedForAvatar(maxDimension: 2048)
            croppingImage = CropImageSource(image: resized, context: .car)
        } catch {
            errorMessage = "Failed to load selected photo"
        }
    }

    private func clearCropping() {
        pickedPhoto = nil
    }

    // MARK: - Upload

    @MainActor
    private func upload(_ cropped: UIImage) async {
        guard !isUploading else { return }
        isUploading = true
        errorMessage = nil
        defer { isUploading = false }

        let resized = cropped.resizedForAvatar(maxDimension: 800)
        guard let data = resized.jpegData(compressionQuality: 0.8) else {
            errorMessage = "Failed to encode photo"
            return
        }

        do {
            let urlString = try await apiService.uploadCarPhoto(carId: carId, data: data)
            guard let url = URL(string: urlString) else {
                errorMessage = "Server returned an invalid photo URL"
                return
            }
            onUploadComplete(url)
            dismiss()
        } catch {
            errorMessage = "Photo upload failed"
            Self.log.error("Car photo upload failed: \(error.localizedDescription)")
        }
    }
}
