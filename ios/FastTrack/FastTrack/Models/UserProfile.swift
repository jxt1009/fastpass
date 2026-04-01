import Foundation
import UIKit
import Combine

// MARK: - UserCar Model

struct UserCar: Codable, Identifiable, Equatable {
    let id: String
    var make: String
    var model: String
    var year: Int?
    var trim: String
    var nickname: String // e.g., "Daily Driver", "Weekend Car", etc.
    
    var displayString: String {
        let parts: [String] = [
            year.map { String($0) } ?? "",
            make,
            model,
            trim
        ].filter { !$0.isEmpty }
        return parts.isEmpty ? "Unknown Car" : parts.joined(separator: " ")
    }
    
    var shortDisplay: String {
        if !nickname.isEmpty {
            return nickname
        }
        let parts = [make, model].filter { !$0.isEmpty }
        return parts.isEmpty ? "Unknown Car" : parts.joined(separator: " ")
    }
    
    init(id: String = UUID().uuidString, make: String, model: String, year: Int? = nil, trim: String = "", nickname: String = "") {
        self.id = id
        self.make = make
        self.model = model
        self.year = year
        self.trim = trim
        self.nickname = nickname
    }
}

// MARK: - UserProfile Model

struct UserProfile: Codable {
    var username: String
    var country: String
    var garage: [UserCar]  // User's collection of cars
    var selectedCarId: String?
    var isPublic: Bool = true
    
    var selectedCar: UserCar? {
        guard let selectedCarId = selectedCarId else { return garage.first }
        return garage.first { $0.id == selectedCarId }
    }
    
    // Legacy car properties for backward compatibility
    var carMake: String { selectedCar?.make ?? "" }
    var carModel: String { selectedCar?.model ?? "" }
    var carYear: Int? { selectedCar?.year }
    var carTrim: String { selectedCar?.trim ?? "" }

    var carDisplayString: String {
        selectedCar?.displayString ?? "No car selected"
    }

    var carShortDisplay: String {
        selectedCar?.shortDisplay ?? "No car selected"
    }

    enum CodingKeys: String, CodingKey {
        case username, country, garage
        case selectedCarId = "selected_car_id"
        case isPublic      = "is_public"
    }

    static var empty: UserProfile {
        UserProfile(username: "", country: "", garage: [], selectedCarId: nil)
    }
    
    mutating func addCarToGarage(_ car: UserCar) {
        garage.append(car)
        if selectedCarId == nil {
            selectedCarId = car.id
        }
    }
    
    mutating func removeCarFromGarage(id: String) {
        garage.removeAll { $0.id == id }
        if selectedCarId == id {
            selectedCarId = garage.first?.id
        }
    }
    
    mutating func updateCarInGarage(_ car: UserCar) {
        if let index = garage.firstIndex(where: { $0.id == car.id }) {
            garage[index] = car
        }
    }
    
    mutating func selectCar(id: String?) {
        selectedCarId = id
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
        // Try loading new format first
        if let data = UserDefaults.standard.data(forKey: profileKey),
           let p = try? JSONDecoder().decode(UserProfile.self, from: data) {
            profile = p
            return
        }
        
        // Migration: Try loading old format and convert
        let oldKey = "user_profile_v1"
        if let data = UserDefaults.standard.data(forKey: oldKey),
           let oldProfile = try? JSONDecoder().decode(OldUserProfile.self, from: data) {
            // Convert to new format
            var car: UserCar? = nil
            if !oldProfile.carMake.isEmpty || !oldProfile.carModel.isEmpty {
                car = UserCar(
                    make: oldProfile.carMake,
                    model: oldProfile.carModel,
                    year: oldProfile.carYear,
                    trim: oldProfile.carTrim,
                    nickname: ""
                )
            }
            
            let newProfile = UserProfile(
                username: oldProfile.username,
                country: oldProfile.country,
                garage: car.map { [$0] } ?? [],
                selectedCarId: car?.id
            )
            
            // Save in new format and remove old
            saveProfile(newProfile)
            UserDefaults.standard.removeObject(forKey: oldKey)
        }
    }
    
    // Legacy profile structure for migration
    private struct OldUserProfile: Codable {
        var username: String
        var country: String
        var carMake: String
        var carModel: String
        var carYear: Int?
        var carTrim: String
        
        enum CodingKeys: String, CodingKey {
            case username, country
            case carMake = "car_make"
            case carModel = "car_model"
            case carYear = "car_year"
            case carTrim = "car_trim"
        }
    }

    func saveProfile(_ p: UserProfile) {
        profile = p
        if let data = try? JSONEncoder().encode(p) {
            UserDefaults.standard.set(data, forKey: profileKey)
        }
        
        // Update on server with error handling
        Task {
            do {
                try await APIService.shared.updateProfile(p)
                print("✅ Profile saved to server successfully")
            } catch {
                print("❌ Failed to save profile to server: \(error)")
                // For now, just log the error. In a production app, you might want to:
                // - Show an error alert
                // - Queue for retry
                // - Mark as dirty for later sync
            }
        }
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
