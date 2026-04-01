import Foundation

// MARK: - NHTSA Response Models

private struct NHTSAResponse: Decodable {
    let Results: [NHTSAModel]
}

private struct NHTSAModel: Decodable {
    let Model_Name: String
}

// MARK: - CarService

class CarService: ObservableObject {
    static let shared = CarService()

    @Published var models: [String] = []
    @Published var isLoading = false
    @Published var error: String?

    private var cache: [String: [String]] = [:]
    private let cacheKey = "nhtsa_models_cache_v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) {
            cache = decoded
        }
    }

    func fetchModels(for make: PerformanceMake) async {
        let key = make.nhtsa

        // Return from cache immediately
        if let cached = cache[key] {
            await MainActor.run {
                self.models = cached.sorted()
                self.isLoading = false
            }
            return
        }

        await MainActor.run { self.isLoading = true; self.error = nil }

        let urlString = "https://vpic.nhtsa.dot.gov/api/vehicles/GetModelsForMake/\(make.urlEncoded)?format=json"
        guard let url = URL(string: urlString) else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(NHTSAResponse.self, from: data)
            let sorted = response.Results.map(\.Model_Name).sorted()

            // Persist cache
            cache[key] = sorted
            if let encoded = try? JSONEncoder().encode(cache) {
                UserDefaults.standard.set(encoded, forKey: cacheKey)
            }

            await MainActor.run {
                self.models = sorted
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = "Could not load models"
                self.isLoading = false
            }
        }
    }

    func clearCache() {
        cache = [:]
        UserDefaults.standard.removeObject(forKey: cacheKey)
    }
}
