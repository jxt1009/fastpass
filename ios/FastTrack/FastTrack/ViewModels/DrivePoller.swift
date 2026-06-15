import Foundation
import Combine

@MainActor
class DrivePoller: ObservableObject {
    @Published var drives: [Drive] = []
    @Published var isLoadingDrives = true

    private var pollTimer: Timer?
    private let apiService: DriveAPI
    private let carStatsManager: CarStatsManager
    private var fetchVersion = 0  // incremented on mutate (delete); in-flight fetches
                                    // check this before applying their result

    init(
        apiService: DriveAPI,
        carStatsManager: CarStatsManager
    ) {
        self.apiService = apiService
        self.carStatsManager = carStatsManager
    }

    func fetchDrives() {
        let versionAtStart = fetchVersion
        Task {
            do {
                let fetched = try await apiService.fetchDrives()
                guard self.fetchVersion == versionAtStart else { return }
                self.drives = fetched
                self.isLoadingDrives = false
            } catch {
                self.isLoadingDrives = false
            }
        }
    }

    /// Called after a local mutation (delete) that would make an in-flight
    /// fetch result stale. The fetch version gate prevents stale data from
    /// overwriting the post-mutation state.
    func invalidateStaleFetches() {
        fetchVersion &+= 1
    }

    func startPolling() {
        guard pollTimer == nil else { return }
        Task { [weak self] in await self?.pollCycle() }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { [weak self] in await self?.pollCycle() }
        }
    }

    private func pollCycle() async {
        do {
            let fetched = try await apiService.fetchDrives()
            self.drives = fetched
            self.isLoadingDrives = false
        } catch {
            self.isLoadingDrives = false
        }
        await recoverPendingDrives()
    }

    private var isRecovering = false

    /// Keys of recently-deleted drives, so recoverPendingDrives can distinguish
    /// "never uploaded" (retry) from "user deleted" (stale file to discard).
    private var recentlyDeletedDriveKeys: Set<String> = []

    func noteDriveDeleted(userID: Int, startTime: Date) {
        let key = "\(userID):\(startTime.timeIntervalSince1970)"
        recentlyDeletedDriveKeys.insert(key)
        invalidateStaleFetches()

        // Also delete the physical file immediately so it can't persist
        // across app restarts when the in-memory set is lost.
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: .temporaryDirectory, includingPropertiesForKeys: nil) else { return }
        for url in entries where url.lastPathComponent.hasPrefix("in_flight_drive_") && url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let drive = try? Self.driveDecoder.decode(Drive.self, from: data),
                  drive.userID == userID,
                  abs(drive.startTime.timeIntervalSince1970 - startTime.timeIntervalSince1970) < 1 else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func recoverPendingDrives(
        in directory: URL = FileManager.default.temporaryDirectory
    ) async {
        guard !isRecovering else { return }
        isRecovering = true
        defer { isRecovering = false }

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
        recentlyDeletedDriveKeys.removeAll(keepingCapacity: true)
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
