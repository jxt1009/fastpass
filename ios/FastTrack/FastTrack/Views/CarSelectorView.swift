import SwiftUI
import PhotosUI
import UIKit

struct CarSelectorView: View {
    @EnvironmentObject var profileManager: ProfileManager
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
                                        .foregroundColor(.blue)
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
    @Environment(\.dismiss) private var dismiss
    @State private var carSelection = CarSelection()
    @State private var nickname = ""
    @State private var showingCarPicker = false

    @State private var pickedPhoto: PhotosPickerItem?
    @State private var pickedImage: UIImage?
    @State private var croppingImage: CropImageSource?
    @State private var uploadedPhotoURL: String?
    @State private var isUploadingPhoto = false
    @State private var isSavingProfile = false
    @State private var photoError: String?

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
                            .foregroundColor(.blue)
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
                    HStack(spacing: 12) {
                        Group {
                            if let pickedImage {
                                Image(uiImage: pickedImage)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.blue.opacity(0.15))
                                    Image(systemName: "car.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 6) {
                            PhotosPicker(selection: $pickedPhoto, matching: .images) {
                                Text(pickedImage == nil ? "Set Photo" : "Change Photo")
                            }
                            .disabled(isUploadingPhoto)

                            if pickedImage != nil || uploadedPhotoURL != nil {
                                Button(role: .destructive) {
                                    removePhoto()
                                } label: {
                                    Text("Remove Photo")
                                }
                                .disabled(isUploadingPhoto)
                            }

                            if isUploadingPhoto || isSavingProfile {
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
            .onChange(of: pickedPhoto) { _, item in
                Task { await loadPickedPhoto(item) }
            }
            .fullScreenCover(item: $croppingImage, onDismiss: {
                pickedPhoto = nil
            }) { source in
                PhotoCropView(image: source.image) { cropped in
                    pickedImage = cropped.resizedForAvatar(maxDimension: 800)
                }
            }
        }
    }

    private func loadPickedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        photoError = nil
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let img = UIImage(data: data) else {
                photoError = "Could not load photo"
                return
            }
            let resized = img.resizedForAvatar(maxDimension: 2048)
            croppingImage = CropImageSource(image: resized)
        } catch {
            photoError = "Failed to load photo"
        }
    }

    private func removePhoto() {
        pickedPhoto = nil
        pickedImage = nil
        uploadedPhotoURL = nil
        photoError = nil
    }

    private func saveCar() {
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
                }
                return
            }
            if let pickedImage {
                await uploadPhoto(for: newCar.id, image: pickedImage)
            }
            await MainActor.run {
                self.isSavingProfile = false
                self.dismiss()
            }
        }
    }

    private func uploadPhoto(for carId: String, image: UIImage) async {
        isUploadingPhoto = true
        defer { isUploadingPhoto = false }
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            photoError = "Failed to encode photo"
            return
        }
        do {
            let url = try await APIService.shared.uploadCarPhoto(carId: carId, data: data)
            await MainActor.run {
                guard var p = self.profileManager.profile else { return }
                p.updateCarPhotoUrl(id: carId, url: url)
                self.profileManager.saveProfile(p)
                self.uploadedPhotoURL = url
            }
        } catch {
            await MainActor.run {
                self.photoError = "Photo upload failed"
            }
        }
    }
}

#Preview {
    CarSelectorView()
        .environmentObject(ProfileManager.shared)
}