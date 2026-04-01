import Foundation
import UIKit
import Combine

// MARK: - Model

struct UserProfile: Codable {
    var username: String
    var country: String
    var carMake: String
    var carModel: String
    var carYear: Int?
    var carTrim: String

    var carDisplayString: String {
        let parts: [String] = [
            carYear.map { String($0) } ?? "",
            carMake,
            carModel,
            carTrim
        ].filter { !$0.isEmpty }
        return parts.isEmpty ? "No car selected" : parts.joined(separator: " ")
    }

    var carShortDisplay: String {
        let parts = [carMake, carModel].filter { !$0.isEmpty }
        return parts.isEmpty ? "No car selected" : parts.joined(separator: " ")
    }

    enum CodingKeys: String, CodingKey {
        case username, country
        case carMake = "car_make"
        case carModel = "car_model"
        case carYear = "car_year"
        case carTrim = "car_trim"
    }

    static var empty: UserProfile {
        UserProfile(username: "", country: "", carMake: "", carModel: "", carYear: nil, carTrim: "")
    }
}

// MARK: - ProfileManager

class ProfileManager: ObservableObject {
    static let shared = ProfileManager()

    @Published var profile: UserProfile?
    @Published var profileImage: UIImage?

    private let profileKey = "user_profile_v2"
    private let avatarFilename = "profile_avatar.jpg"

    private init() {
        loadProfile()
        loadAvatar()
    }

    var isProfileComplete: Bool {
        guard let p = profile else { return false }
        return !p.username.isEmpty
    }

    func loadProfile() {
        if let data = UserDefaults.standard.data(forKey: profileKey),
           let p = try? JSONDecoder().decode(UserProfile.self, from: data) {
            profile = p
        }
    }

    func saveProfile(_ p: UserProfile) {
        profile = p
        if let data = try? JSONEncoder().encode(p) {
            UserDefaults.standard.set(data, forKey: profileKey)
        }
        Task { try? await APIService.shared.updateProfile(p) }
    }

    func saveAvatar(_ image: UIImage) {
        profileImage = image
        if let data = image.jpegData(compressionQuality: 0.8) {
            try? data.write(to: avatarURL())
        }
    }

    func loadAvatar() {
        if let data = try? Data(contentsOf: avatarURL()) {
            profileImage = UIImage(data: data)
        }
    }

    func clearProfile() {
        profile = nil
        profileImage = nil
        UserDefaults.standard.removeObject(forKey: profileKey)
        try? FileManager.default.removeItem(at: avatarURL())
    }

    private func avatarURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(avatarFilename)
    }
}
