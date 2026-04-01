import Foundation
import Combine

// MARK: - Array Extension

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

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
    private let cacheKey = "nhtsa_models_cache_v2"
    
    // Popular makes to preload
    private let popularMakes = ["BMW", "Mercedes-Benz", "Audi", "Chevrolet", "Porsche", "Tesla", "Ferrari", "Lamborghini"]

    private init() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) {
            cache = decoded
        }
        
        // Preload popular makes in background
        Task {
            await preloadPopularMakes()
        }
    }
    
    private func preloadPopularMakes() async {
        // Preload in smaller batches to improve initial app load
        let batches = popularMakes.chunked(into: 3)
        
        for batch in batches {
            await withTaskGroup(of: Void.self) { group in
                for make in batch {
                    if cache[make] == nil {
                        group.addTask {
                            await self.fetchModelsInternal(for: make)
                        }
                    }
                }
            }
            // Shorter delay between batches
            try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 second
        }
    }

    func fetchModels(for make: PerformanceMake) async {
        await fetchModelsInternal(for: make.nhtsa)
    }
    
    private func fetchModelsInternal(for nhtsa: String) async {
        let key = nhtsa

        // Return from cache immediately
        if let cached = cache[key] {
            await MainActor.run {
                self.models = cached.sorted()
                self.isLoading = false
            }
            return
        }

        await MainActor.run { self.isLoading = true; self.error = nil }

        let urlString = "https://vpic.nhtsa.dot.gov/api/vehicles/GetModelsForMake/\(nhtsa.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? nhtsa)?format=json"
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
