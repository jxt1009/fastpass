import SwiftUI
import PhotosUI
import UIKit

struct CarSelectorView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var apiService: APIService
    @Environment(\.dismiss) private var dismiss
    @State private var showingAddCar = false

    var body: some View {
        NavigationStack {
            Group {
                if let profile = profileManager.profile, !profile.garage.isEmpty {
                    List(profile.garage) { car in
                        Button {
                            var updatedProfile = profile
                            updatedProfile.selectCar(id: car.id)
                            profileManager.saveProfile(updatedProfile)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(car.shortDisplay)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text(car.displayString)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if profile.selectedCarId == car.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.ftBlue)
                                }
                            }
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No Cars in Garage",
                        systemImage: "car",
                        description: Text("Add a car to your garage to start tracking drives")
                    )
                }
            }
            .navigationTitle("Select Car")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddCar = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddCar) {
                AddCarView()
            }
        }
    }
}

struct AddCarView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var apiService: APIService
    @Environment(\.dismiss) private var dismiss
    @State private var carSelection = CarSelection()
    @State private var nickname = ""
    @State private var showingCarPicker = false

    @State private var pickedImage: UIImage?
    @State private var uploadedPhotoURL: String?
    @State private var isUploadingPhoto = false
    @State private var isSavingProfile = false
    @State private var photoError: String?
    @State private var savedCarId: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Car Details") {
                    if carSelection.isComplete {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(carSelection.displayString)
                                .font(.headline)
                            Button("Change Car") {
                                showingCarPicker = true
                            }
                            .font(.subheadline)
                            .foregroundColor(.ftBlue)
                        }
                    } else {
                        Button("Select Car") {
                            showingCarPicker = true
                        }
                    }
                }

                Section("Nickname (Optional)") {
                    TextField("e.g., Daily Driver, Track Car", text: $nickname)
                }

                Section("Photo") {
                    CarPhotoEditorSection(
                        pickedImage: $pickedImage,
                        existingPhotoURL: uploadedPhotoURL,
                        isUploading: isUploadingPhoto || isSavingProfile,
                        errorMessage: photoError,
                        onRemove: removePhoto
                    )
                }
            }
            .navigationTitle("Add Car")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isSavingProfile ? "Saving…" : "Save") {
                        saveCar()
                    }
                    .disabled(!carSelection.isComplete || isUploadingPhoto || isSavingProfile)
                }
            }
            .sheet(isPresented: $showingCarPicker) {
                CarPickerView(selection: $carSelection)
            }
        }
    }

    private func removePhoto() {
        pickedImage = nil
        uploadedPhotoURL = nil
        photoError = nil
    }

    private func saveCar() {
        if savedCarId != nil {
            isSavingProfile = true
            Task { await completeSave() }
            return
        }

        guard let make = carSelection.make,
              var profile = profileManager.profile else { return }

        let newCar = UserCar(
            make: make.displayName,
            model: carSelection.model,
            year: carSelection.year,
            trim: carSelection.trim,
            nickname: nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        profile.addCarToGarage(newCar)
        savedCarId = newCar.id
        isSavingProfile = true
        let saveTask = profileManager.saveProfile(profile)

        // Await the server save before doing anything that depends on the
        // server having the new car in its garage (e.g. the photo upload,
        // which would 404 "car not found in garage" otherwise). The sheet
        // stays open so the user sees upload progress and errors.
        Task {
            do {
                try await saveTask.value
            } catch {
                await MainActor.run {
                    self.photoError = "Profile save failed"
                    self.isSavingProfile = false
                    self.savedCarId = nil
                }
                return
            }
            await completeSave()
        }
    }

    private func completeSave() async {
        guard let carId = savedCarId else {
            await MainActor.run { self.isSavingProfile = false }
            return
        }
        if let pickedImage, uploadedPhotoURL == nil {
            let uploaded = await uploadPhoto(for: carId, image: pickedImage)
            if !uploaded {
                await MainActor.run { self.isSavingProfile = false }
                return
            }
        }
        await MainActor.run {
            self.isSavingProfile = false
            self.dismiss()
        }
    }

    @discardableResult
    private func uploadPhoto(for carId: String, image: UIImage) async -> Bool {
        isUploadingPhoto = true
        defer { isUploadingPhoto = false }
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            photoError = "Failed to encode photo"
            return false
        }
        do {
            let url = try await apiService.uploadCarPhoto(carId: carId, data: data)
            await MainActor.run {
                guard var p = self.profileManager.profile else { return }
                p.updateCarPhotoUrl(id: carId, url: url)
                self.profileManager.saveProfile(p)
                self.uploadedPhotoURL = url
            }
            return true
        } catch {
            await MainActor.run {
                self.photoError = "Photo upload failed"
            }
            return false
        }
    }
}

#Preview {
    let apiService = APIService()
    let authManager = AuthManager(apiService: apiService)
    apiService.authManager = authManager
    return CarSelectorView()
        .environmentObject(ProfileManager(apiService: apiService))
}
