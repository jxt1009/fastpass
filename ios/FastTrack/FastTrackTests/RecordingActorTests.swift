import XCTest
import CoreLocation
@testable import FastTrack

final class RecordingActorTests: XCTestCase {

    @MainActor
    func test_actorIsolatesState() async {
        let actor = RecordingActor()
        // First ingest: always published (or coalesced by the actor's
        // own internal rate cap; for a single sample the cap is
        // irrelevant).
        await actor.ingestRoutePoint(.init(latitude: 1, longitude: 2), speed: 10, timestamp: 1)
        let snap = await actor.snapshot()
        XCTAssertEqual(snap.routePointCount, 1)
        XCTAssertEqual(snap.runningMaxSpeed, 10)
    }

    func test_runningStatsAfterManyIngests() async {
        let actor = RecordingActor()
        for i in 0..<1000 {
            let speed = Double(i % 50)
            await actor.ingestRoutePoint(
                .init(latitude: Double(i) * 0.0001, longitude: 0),
                speed: speed,
                timestamp: Double(i)
            )
        }
        let snap = await actor.snapshot()
        XCTAssertEqual(snap.routePointCount, 1000)
        XCTAssertEqual(snap.runningMaxSpeed, 49)
        XCTAssertEqual(snap.runningMinSpeed, 0)
        XCTAssertGreaterThan(snap.runningAvgSpeed, 0)
    }

    func test_snapshotThrottledToTenHertz() async {
        let actor = RecordingActor()
        let now = Date()
        for i in 0..<50 {
            await actor.ingestRoutePoint(
                .init(latitude: 0, longitude: Double(i) * 0.0001),
                speed: 20,
                timestamp: Double(i) * 0.001  // 1ms apart → 1000 Hz
            )
        }
        // Snapshot at the same wall-clock instant multiple times —
        // actor must internally rate-limit publishes.
        let s1 = await actor.snapshot(now: now)
        let s2 = await actor.snapshot(now: now.addingTimeInterval(0.05))   // 50ms < 100ms
        let s3 = await actor.snapshot(now: now.addingTimeInterval(0.2))    // 200ms > 100ms
        // s1 and s2 should match; s3 should reflect a later publish.
        XCTAssertEqual(s1.publishedAt, s2.publishedAt)
        XCTAssertNotEqual(s2.publishedAt, s3.publishedAt)
    }
}
