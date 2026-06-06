import XCTest
@testable import FastTrack

final class UserCarPhotoTests: XCTestCase {

    // MARK: - Photo URL decoding

    /// A server JSON snippet with `photo_url` set should decode to a UserCar
    /// whose `photoUrl` matches.
    func testUserCar_DecodesPhotoUrlFromServer() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "make": "Honda",
          "model": "Civic Type R",
          "year": 2018,
          "trim": "Limited Edition",
          "nickname": "Track Toy",
          "photo_url": "https://fast.toper.dev/uploads/garage_cars/1_xxx.png"
        }
        """.data(using: .utf8)!

        let car = try JSONDecoder().decode(UserCar.self, from: json)
        XCTAssertEqual(car.id, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(car.make, "Honda")
        XCTAssertEqual(car.model, "Civic Type R")
        XCTAssertEqual(car.year, 2018)
        XCTAssertEqual(car.trim, "Limited Edition")
        XCTAssertEqual(car.nickname, "Track Toy")
        XCTAssertEqual(car.photoUrl, "https://fast.toper.dev/uploads/garage_cars/1_xxx.png")
        XCTAssertTrue(car.hasPhoto)
    }

    /// A server JSON snippet without `photo_url` should decode to a UserCar
    /// whose `photoUrl` is nil and `hasPhoto` is false.
    func testUserCar_DecodesMissingPhotoUrlAsNil() throws {
        let json = """
        {
          "id": "22222222-2222-2222-2222-222222222222",
          "make": "Subaru",
          "model": "WRX",
          "year": 2020,
          "trim": "STI",
          "nickname": "Daily"
        }
        """.data(using: .utf8)!

        let car = try JSONDecoder().decode(UserCar.self, from: json)
        XCTAssertNil(car.photoUrl)
        XCTAssertFalse(car.hasPhoto)
    }

    /// An empty photo_url from the server should be treated as "no photo".
    func testUserCar_EmptyPhotoUrlIsNotHasPhoto() throws {
        let json = """
        {
          "id": "33333333-3333-3333-3333-333333333333",
          "make": "Mazda",
          "model": "MX-5",
          "year": 2015,
          "trim": "",
          "nickname": "",
          "photo_url": ""
        }
        """.data(using: .utf8)!

        let car = try JSONDecoder().decode(UserCar.self, from: json)
        XCTAssertEqual(car.photoUrl, "")
        XCTAssertFalse(car.hasPhoto)
    }

    // MARK: - Photo URL round-trip

    /// Encoding then decoding a UserCar with a photo URL should preserve it.
    func testUserCar_RoundTripsPhotoUrl() throws {
        let original = UserCar(
            id: "44444444-4444-4444-4444-444444444444",
            make: "BMW",
            model: "M3",
            year: 2019,
            trim: "Competition",
            nickname: "Weekend",
            photoUrl: "https://fast.toper.dev/uploads/garage_cars/1_yyy.jpg"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(UserCar.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.photoUrl, original.photoUrl)
    }

    /// The on-wire key for photoUrl is "photo_url" (snake_case), matching the
    /// rest of the JSON contract.
    func testUserCar_PhotoUrlWireKey() throws {
        let car = UserCar(
            id: "55555555-5555-5555-5555-555555555555",
            make: "Audi",
            model: "RS5",
            year: 2022,
            trim: "",
            nickname: "",
            photoUrl: "https://fast.toper.dev/uploads/garage_cars/1_zzz.png"
        )

        let data = try JSONEncoder().encode(car)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"photo_url\""), "expected snake_case photo_url in wire JSON, got: \(json)")
        XCTAssertFalse(json.contains("photoUrl"), "did not expect camelCase photoUrl in wire JSON, got: \(json)")
    }

    // MARK: - UserProfile.updateCarPhotoUrl

    /// updateCarPhotoUrl should mutate only the matching car and preserve the
    /// rest of the garage.
    func testUserProfile_updateCarPhotoUrl_UpdatesMatchingCar() {
        var profile = UserProfile(username: "tester", country: "US", garage: [], selectedCarId: nil)
        let carA = UserCar(id: "a", make: "Honda", model: "Civic")
        let carB = UserCar(id: "b", make: "Toyota", model: "GR86")
        profile.addCarToGarage(carA)
        profile.addCarToGarage(carB)

        profile.updateCarPhotoUrl(id: "a", url: "https://fast.toper.dev/uploads/garage_cars/x.png")

        XCTAssertEqual(profile.garage[0].photoUrl, "https://fast.toper.dev/uploads/garage_cars/x.png")
        XCTAssertNil(profile.garage[1].photoUrl)
    }

    /// Passing nil or an empty URL to updateCarPhotoUrl should clear the field.
    func testUserProfile_updateCarPhotoUrl_ClearsOnNilOrEmpty() {
        var profile = UserProfile(username: "tester", country: "US", garage: [], selectedCarId: nil)
        let car = UserCar(id: "a", make: "Honda", model: "Civic", photoUrl: "https://example.com/x.png")
        profile.addCarToGarage(car)

        profile.updateCarPhotoUrl(id: "a", url: nil)
        XCTAssertNil(profile.garage[0].photoUrl)

        profile.updateCarPhotoUrl(id: "a", url: "https://example.com/y.png")
        XCTAssertEqual(profile.garage[0].photoUrl, "https://example.com/y.png")

        profile.updateCarPhotoUrl(id: "a", url: "")
        XCTAssertNil(profile.garage[0].photoUrl)
    }

    // MARK: - EditCarView round-trip

    /// Simulates the EditCarView save flow: build a UserProfile with one car,
    /// mutate nickname and photoUrl, apply via `updateCarInGarage`, and verify
    /// the edited values stick while identity fields (id, make, model, year,
    /// trim) and the rest of the garage are preserved.
    func testEditCarView_RoundTripsNicknameAndPhotoUrl() {
        var profile = UserProfile(username: "tester", country: "US", garage: [], selectedCarId: nil)
        let original = UserCar(
            id: "car-1",
            make: "Honda",
            model: "Civic Type R",
            year: 2018,
            trim: "Limited Edition",
            nickname: "Old Name",
            photoUrl: "https://fast.toper.dev/uploads/garage_cars/old.png"
        )
        let other = UserCar(
            id: "car-2",
            make: "Toyota",
            model: "GR86",
            year: 2023,
            trim: "",
            nickname: "Weekend",
            photoUrl: "https://fast.toper.dev/uploads/garage_cars/other.png"
        )
        profile.addCarToGarage(original)
        profile.addCarToGarage(other)

        var edited = original
        edited.nickname = "Track Toy"
        edited.photoUrl = "https://fast.toper.dev/uploads/garage_cars/new.jpg"
        profile.updateCarInGarage(edited)

        XCTAssertEqual(profile.garage.count, 2)
        XCTAssertEqual(profile.garage[0].id, "car-1")
        XCTAssertEqual(profile.garage[0].make, "Honda")
        XCTAssertEqual(profile.garage[0].model, "Civic Type R")
        XCTAssertEqual(profile.garage[0].year, 2018)
        XCTAssertEqual(profile.garage[0].trim, "Limited Edition")
        XCTAssertEqual(profile.garage[0].nickname, "Track Toy")
        XCTAssertEqual(profile.garage[0].photoUrl, "https://fast.toper.dev/uploads/garage_cars/new.jpg")
        XCTAssertTrue(profile.garage[0].hasPhoto)

        // Sibling car is untouched
        XCTAssertEqual(profile.garage[1].id, "car-2")
        XCTAssertEqual(profile.garage[1].nickname, "Weekend")
        XCTAssertEqual(profile.garage[1].photoUrl, "https://fast.toper.dev/uploads/garage_cars/other.png")
    }

    /// When the user removes a photo in EditCarView, the saved car must have
    /// `photoUrl == nil` and `hasPhoto == false`. Mirrors the
    /// `workingPhotoUrl == nil && originalPhotoUrl != nil` branch in the
    /// view's save() — the actual `deleteCarPhoto` API call is not invoked
    /// here (it would require a network mock), but the model-level mutation
    /// is what EditCarView would persist before/after that call.
    func testEditCarView_RemovingPhotoClearsPhotoUrl() {
        var profile = UserProfile(username: "tester", country: "US", garage: [], selectedCarId: nil)
        let car = UserCar(
            id: "car-1",
            make: "Honda",
            model: "Civic",
            photoUrl: "https://fast.toper.dev/uploads/garage_cars/old.png"
        )
        profile.addCarToGarage(car)

        var edited = car
        edited.photoUrl = nil
        profile.updateCarInGarage(edited)

        XCTAssertNil(profile.garage[0].photoUrl)
        XCTAssertFalse(profile.garage[0].hasPhoto)
        // Other identity fields preserved
        XCTAssertEqual(profile.garage[0].id, "car-1")
        XCTAssertEqual(profile.garage[0].make, "Honda")
        XCTAssertEqual(profile.garage[0].model, "Civic")
    }
}
