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
        // Preload in smaller batches to improve initial app load.
        // Uses the non-mutating fetchModels(for:) so background fetches
        // don't overwrite the shared models/isLoading/error state while
        // the picker is open for a different make.
        let batches = popularMakes.chunked(into: 3)
        
        for batch in batches {
            await withTaskGroup(of: Void.self) { group in
                for make in batch {
                    if cache[make] == nil {
                        group.addTask {
                            _ = try? await self.fetchModels(for: make)
                        }
                    }
                }
            }
            // Shorter delay between batches
            try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 second
        }
    }

    /// Fetches models for the given make and updates shared published state.
    /// Used by the active picker UI (ModelPickerView).
    func fetchModels(for make: PerformanceMake) async {
        let key = make.nhtsa

        // Return from cache immediately without showing a loading state
        if let cached = cache[key] {
            await MainActor.run {
                self.models = cached.sorted()
                self.isLoading = false
            }
            return
        }

        await MainActor.run { self.isLoading = true; self.error = nil }

        do {
            let sorted = try await fetchModelsRemote(for: key)
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

    /// Fetches models for a make and returns them directly without touching shared state.
    /// Safe to call from background preloads while the picker is visible.
    func fetchModels(for make: String) async throws -> [String] {
        if let cached = cache[make] {
            return cached.sorted()
        }
        return try await fetchModelsRemote(for: make)
    }

    private func fetchModelsRemote(for nhtsa: String) async throws -> [String] {
        let urlString = "https://vpic.nhtsa.dot.gov/api/vehicles/GetModelsForMake/\(nhtsa.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? nhtsa)?format=json"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(NHTSAResponse.self, from: data)
        let sorted = response.Results.map(\.Model_Name).sorted()

        // Persist to cache
        cache[nhtsa] = sorted
        if let encoded = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(encoded, forKey: cacheKey)
        }

        return sorted
    }

    func clearCache() {
        cache = [:]
        UserDefaults.standard.removeObject(forKey: cacheKey)
    }
}
