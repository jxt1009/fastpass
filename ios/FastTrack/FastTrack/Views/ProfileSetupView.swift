import SwiftUI
import PhotosUI

struct ProfileSetupView: View {
    @StateObject private var profileManager = ProfileManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var country = ""
    @State private var carSelection = CarSelection()
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var avatarImage: UIImage?
    @State private var showCarPicker = false
    @State private var isSaving = false
    @State private var usernameError = ""

    private var isValid: Bool { username.count >= 3 && username.count <= 20 && usernameError.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                // Avatar
                Section {
                    HStack {
                        Spacer()
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            ZStack {
                                if let img = avatarImage {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 90, height: 90)
                                        .clipShape(Circle())
                                } else {
                                    Circle()
                                        .fill(Color.blue.opacity(0.15))
                                        .frame(width: 90, height: 90)
                                    Image(systemName: "camera.fill")
                                        .font(.title2)
                                        .foregroundColor(.blue)
                                }
                                Circle()
                                    .stroke(Color.blue, lineWidth: 2)
                                    .frame(width: 90, height: 90)
                            }
                        }
                        .onChange(of: selectedPhoto) { _, item in
                            Task {
                                if let data = try? await item?.loadTransferable(type: Data.self),
                                   let img = UIImage(data: data) {
                                    avatarImage = img
                                }
                            }
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                // Profile info
                Section("Profile") {
                    HStack {
                        TextField("Username", text: $username)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        if !usernameError.isEmpty {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.red)
                        } else if username.count >= 3 {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                    if !usernameError.isEmpty {
                        Text(usernameError).font(.caption).foregroundColor(.red)
                    }
                    TextField("Country (optional)", text: $country)
                        .autocorrectionDisabled()
                }
                .onChange(of: username) { _, val in validateUsername(val) }

                // Car
                Section("Your Car") {
                    Button {
                        showCarPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "car.fill")
                                .foregroundColor(.blue)
                            if carSelection.isComplete {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(carSelection.displayString)
                                        .foregroundColor(.primary)
                                        .fontWeight(.medium)
                                }
                            } else {
                                Text("Select a car")
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    if carSelection.isComplete {
                        Button("Remove car", role: .destructive) {
                            carSelection = CarSelection()
                        }
                    }
                }
            }
            .navigationTitle(profileManager.isProfileComplete ? "Edit Profile" : "Set Up Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid || isSaving)
                        .fontWeight(.semibold)
                }
                if profileManager.isProfileComplete {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .sheet(isPresented: $showCarPicker) {
                CarPickerView(selection: $carSelection)
            }
            .onAppear { loadExisting() }
        }
    }

    private func loadExisting() {
        if let p = profileManager.profile {
            username = p.username
            country = p.country
            
            // Load car from garage or legacy fields
            if let selectedCar = p.selectedCar {
                let make = performanceMakes.first { $0.displayName == selectedCar.make }
                carSelection = CarSelection(
                    make: make,
                    model: selectedCar.model,
                    year: selectedCar.year,
                    trim: selectedCar.trim
                )
            }
        }
        avatarImage = profileManager.profileImage
    }

    private func validateUsername(_ val: String) {
        if val.isEmpty { usernameError = ""; return }
        if val.count < 3 { usernameError = "Must be at least 3 characters"; return }
        if val.count > 20 { usernameError = "Maximum 20 characters"; return }
        if val.contains(" ") { usernameError = "No spaces allowed"; return }
        usernameError = ""
    }

    private func save() {
        guard isValid else { return }
        isSaving = true
        
        // Create garage with selected car if any
        var garage: [UserCar] = []
        var selectedCarId: String? = nil
        
        if let make = carSelection.make, !carSelection.model.isEmpty {
            let car = UserCar(
                make: make.displayName,
                model: carSelection.model,
                year: carSelection.year,
                trim: carSelection.trim,
                nickname: ""
            )
            garage = [car]
            selectedCarId = car.id
        }
        
        let p = UserProfile(
            username: username,
            country: country,
            garage: garage,
            selectedCarId: selectedCarId
        )
        profileManager.saveProfile(p)
        if let img = avatarImage { profileManager.saveAvatar(img) }
        isSaving = false
        dismiss()
    }
}
