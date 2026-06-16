import SwiftUI
import PhotosUI

struct ProfileSetupView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var country = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var avatarImage: UIImage?
    @State private var croppingImage: CropImageSource?
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
                            Task { await loadPickedPhoto(item) }
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
            }
            .scrollContentBackground(.hidden)
            .background(Color.ftBgGradient, ignoresSafeAreaEdges: .all)
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
            .onAppear { loadExisting() }
            .fullScreenCover(item: $croppingImage, onDismiss: {
                selectedPhoto = nil
            }) { source in
                PhotoCropView(image: source.image, context: source.context) { cropped in
                    avatarImage = cropped.resizedForAvatar(maxDimension: 800)
                }
            }
        }
    }

    private func loadExisting() {
        if let p = profileManager.profile {
            username = p.username
            country = p.country
        }
        avatarImage = profileManager.profileImage
    }

    @MainActor
    private func loadPickedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let img = UIImage(data: data) else {
            selectedPhoto = nil
            return
        }
        let resized = img.resizedForAvatar(maxDimension: 2048)
        croppingImage = CropImageSource(image: resized, context: .avatar)
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
        
        // Preserve existing id, garage, car selection, and privacy so editing
        // the profile doesn't clobber the leaderboard "You" marker, garage, or
        // the user's privacy choice.
        var updatedProfile = UserProfile(
            id: profileManager.profile?.id,
            username: username,
            country: country,
            garage: profileManager.profile?.garage ?? [],
            selectedCarId: profileManager.profile?.selectedCarId,
            isPublic: profileManager.profile?.isPublic ?? true
        )
        
        profileManager.saveProfile(updatedProfile)
        if let img = avatarImage { profileManager.saveAvatar(img) }
        isSaving = false
        dismiss()
    }
}
