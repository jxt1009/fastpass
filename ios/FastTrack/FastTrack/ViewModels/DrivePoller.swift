import Foundation
import Combine

@MainActor
class DrivePoller: ObservableObject {
    @Published var drives: [Drive] = []
    @Published var isLoadingDrives = true

    private var pollTimer: Timer?
    private let apiService: DriveAPI
    private let carStatsManager: CarStatsManager

    init(
        apiService: DriveAPI,
        carStatsManager: CarStatsManager
    ) {
        self.apiService = apiService
        self.carStatsManager = carStatsManager
    }

    func fetchDrives() {
        Task {
            do {
                let fetched = try await apiService.fetchDrives()
                self.drives = fetched
                self.isLoadingDrives = false
            } catch {
                self.isLoadingDrives = false
            }
        }
    }

    func startPolling() {
        guard pollTimer == nil else { return }
        fetchDrives()
        Task { [weak self] in await self?.recoverPendingDrives() }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.fetchDrives()
            Task { [weak self] in await self?.recoverPendingDrives() }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func recoverPendingDrives(
        in directory: URL = FileManager.default.temporaryDirectory
    ) async {
        let fm = FileManager.default
        let entries: [URL]
        do {
            entries = try fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
        } catch {
            return
        }
        let candidates = entries.filter { url in
            url.lastPathComponent.hasPrefix("in_flight_drive_") &&
            url.pathExtension == "json"
        }
        guard !candidates.isEmpty else { return }

        // Fetch the current server-side list so we can skip stale files.
        let serverDrives: [Drive]
        do {
            serverDrives = try await apiService.fetchDrives()
            self.drives = serverDrives
        } catch {
            serverDrives = self.drives  // fall back to local cache
        }

        for url in candidates {
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            let drive: Drive
            do {
                drive = try Self.driveDecoder.decode(Drive.self, from: data)
            } catch {
                try? FileManager.default.removeItem(at: url)
                continue
            }

            // Dedup: if a drive with this start time and user ID already
            // exists on the server, the in-flight file is stale.
            if serverDrives.contains(where: { $0.startTime == drive.startTime && $0.userID == drive.userID }) {
                try? FileManager.default.removeItem(at: url)
                continue
            }

            do {
                let saved = try await apiService.createDrive(drive)
                self.drives.insert(saved, at: 0)
                self.carStatsManager.updateStats(for: saved)
                try? FileManager.default.removeItem(at: url)
            } catch {
            }
        }
    }

    private static let driveDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func clearDrives() {
        drives = []
        isLoadingDrives = false
    }
}
