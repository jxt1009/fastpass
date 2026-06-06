import SwiftUI
import PhotosUI
import UIKit

struct EditCarView: View {
    let carId: String
    @EnvironmentObject var profileManager: ProfileManager
    @Environment(\.dismiss) private var dismiss

    @State private var nickname: String = ""
    @State private var originalPhotoUrl: String?
    @State private var workingPhotoUrl: String?
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var pickedImage: UIImage?
    @State private var isUploadingPhoto = false
    @State private var photoError: String?
    @State private var isSaving = false
    @State private var didLoadInitialState = false

    private var car: UserCar? {
        profileManager.profile?.garage.first(where: { $0.id == carId })
    }

    var body: some View {
        NavigationStack {
            Form {
                if let car {
                    Section("Car") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(car.displayString)
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text("ID: \(car.id.prefix(8))…")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    Section("Nickname") {
                        TextField("e.g., Daily Driver, Track Car", text: $nickname)
                    }

                    Section("Photo") {
                        photoSection
                    }
                } else {
                    Section {
                        ContentUnavailableView(
                            "Car not found",
                            systemImage: "exclamationmark.triangle",
                            description: Text("This car is no longer in your garage.")
                        )
                    }
                }
            }
            .navigationTitle("Edit Car")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(car == nil || isSaving || isUploadingPhoto)
                }
            }
            .onAppear { loadInitialStateIfNeeded() }
            .onChange(of: pickedPhoto) { _, item in
                Task { await loadPickedPhoto(item) }
            }
        }
    }

    // MARK: - Photo section

    @ViewBuilder
    private var photoSection: some View {
        HStack(spacing: 12) {
            Group {
                if let pickedImage {
                    Image(uiImage: pickedImage)
                        .resizable()
                        .scaledToFill()
                } else if let url = workingPhotoUrl, !url.isEmpty,
                          let photoURL = URL(string: url) {
                    AsyncImage(url: photoURL) { phase in
                        switch phase {
                        case .empty:
                            photoPlaceholder
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            photoPlaceholder
                        @unknown default:
                            photoPlaceholder
                        }
                    }
                } else {
                    photoPlaceholder
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                PhotosPicker(selection: $pickedPhoto, matching: .images) {
                    Text(photoButtonTitle)
                }
                .disabled(isUploadingPhoto)

                if pickedImage != nil || workingPhotoUrl != nil {
                    Button(role: .destructive) {
                        removePhoto()
                    } label: {
                        Text("Remove Photo")
                    }
                    .disabled(isUploadingPhoto)
                }

                if isUploadingPhoto {
                    ProgressView()
                        .controlSize(.small)
                }
                if let photoError {
                    Text(photoError)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
    }

    private var photoPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.blue.opacity(0.15))
            Image(systemName: "car.fill")
                .foregroundColor(.blue)
        }
    }

    private var photoButtonTitle: String {
        if pickedImage != nil { return "Change Photo" }
        if workingPhotoUrl != nil && !workingPhotoUrl!.isEmpty { return "Change Photo" }
        return "Set Photo"
    }

    // MARK: - State management

    private func loadInitialStateIfNeeded() {
        guard !didLoadInitialState, let car else { return }
        didLoadInitialState = true
        nickname = car.nickname
        originalPhotoUrl = car.photoUrl
        workingPhotoUrl = car.photoUrl
    }

    @MainActor
    private func loadPickedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        photoError = nil
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let img = UIImage(data: data) else {
                photoError = "Could not load photo"
                return
            }
            let resized = img.resizedForAvatar(maxDimension: 800)
            pickedImage = resized
        } catch {
            photoError = "Failed to load photo"
        }
    }

    private func removePhoto() {
        pickedPhoto = nil
        pickedImage = nil
        workingPhotoUrl = nil
        photoError = nil
    }

    // MARK: - Save

    @MainActor
    private func save() async {
        guard let car, var profile = profileManager.profile else { return }
        isSaving = true
        defer { isSaving = false }

        var updatedCar = car
        updatedCar.nickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)

        if let pickedImage {
            isUploadingPhoto = true
            defer { isUploadingPhoto = false }
            guard let data = pickedImage.jpegData(compressionQuality: 0.8) else {
                photoError = "Failed to encode photo"
                return
            }
            do {
                let url = try await APIService.shared.uploadCarPhoto(carId: carId, data: data)
                updatedCar.photoUrl = url
            } catch {
                photoError = "Photo upload failed"
                return
            }
        } else if workingPhotoUrl == nil && originalPhotoUrl != nil {
            do {
                try await APIService.shared.deleteCarPhoto(carId: carId)
                updatedCar.photoUrl = nil
            } catch {
                photoError = "Failed to remove photo"
                return
            }
        } else {
            updatedCar.photoUrl = workingPhotoUrl
        }

        profile.updateCarInGarage(updatedCar)
        profileManager.saveProfile(profile)
        dismiss()
    }
}
