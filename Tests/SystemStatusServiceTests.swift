import XCTest
@testable import TimeVault

final class SystemStatusServiceTests: XCTestCase {
    func testParsesTimeMachineLocalSnapshotDate() {
        let date = SystemStatusService.snapshotDate(in: "com.apple.TimeMachine.2026-07-23-143015.local")

        let components = date.map { Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: $0) }
        XCTAssertEqual(components?.year, 2026)
        XCTAssertEqual(components?.month, 7)
        XCTAssertEqual(components?.day, 23)
        XCTAssertEqual(components?.hour, 14)
        XCTAssertEqual(components?.minute, 30)
        XCTAssertEqual(components?.second, 15)
    }

    func testParsesBackupDateFromMountedPath() {
        let path = "/Volumes/.timemachine/machine/2026-07-23-175646.backup/2026-07-23-175646.backup"
        let date = SystemStatusService.snapshotDate(in: path)

        let components = date.map { Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: $0) }
        XCTAssertEqual(components?.year, 2026)
        XCTAssertEqual(components?.month, 7)
        XCTAssertEqual(components?.day, 23)
        XCTAssertEqual(components?.hour, 17)
        XCTAssertEqual(components?.minute, 56)
        XCTAssertEqual(components?.second, 46)
    }

    func testIgnoresNamesWithoutTimestamp() {
        XCTAssertNil(SystemStatusService.snapshotDate(in: "com.apple.TimeMachine.local"))
    }

    func testIgnoresTMUtilHeaderWhenParsingSnapshotNames() {
        let output = """
        Snapshots for disk /:
        com.apple.TimeMachine.2026-07-23-143015.local
        """

        XCTAssertEqual(
            SystemStatusService.snapshotNames(in: output),
            ["com.apple.TimeMachine.2026-07-23-143015.local"]
        )
    }

}
