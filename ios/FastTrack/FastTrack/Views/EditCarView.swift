import SwiftUI
import PhotosUI
import UIKit
struct EditCarView: View {
    let carId: String

    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var apiService: APIService
    @Environment(\.dismiss) private var dismiss

    @State private var nickname: String = ""
    @State private var originalPhotoUrl: String?
    @State private var workingPhotoUrl: String?
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
                        CarPhotoEditorSection(
                            pickedImage: $pickedImage,
                            existingPhotoURL: workingPhotoUrl,
                            isUploading: isUploadingPhoto,
                            errorMessage: photoError,
                            onRemove: removePhoto
                        )
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
        }
    }

    // MARK: - State management

    private func loadInitialStateIfNeeded() {
        guard !didLoadInitialState, let car else { return }
        didLoadInitialState = true
        nickname = car.nickname
        originalPhotoUrl = car.photoUrl
        workingPhotoUrl = car.photoUrl
    }

    private func removePhoto() {
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
                let url = try await apiService.uploadCarPhoto(carId: carId, data: data)
                updatedCar.photoUrl = url
            } catch {
                photoError = "Photo upload failed"
                return
            }
        } else if workingPhotoUrl == nil && originalPhotoUrl != nil {
            do {
                try await apiService.deleteCarPhoto(carId: carId)
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
