import XCTest
@testable import ColimaUI

final class LocalDomainsAutopilotPolicyTests: XCTestCase {
    func testRepairAllowedForManual() {
        XCTAssertTrue(LocalDomainsAutopilotPolicy.shouldAttemptRepair(trigger: .manual))
    }

    func testRepairAllowedForSettingsChange() {
        XCTAssertTrue(LocalDomainsAutopilotPolicy.shouldAttemptRepair(trigger: .settingsChange))
    }

    func testRepairNotAllowedForPeriodic() {
        XCTAssertFalse(LocalDomainsAutopilotPolicy.shouldAttemptRepair(trigger: .periodic))
    }

    func testRepairNotAllowedForDockerEvent() {
        XCTAssertFalse(LocalDomainsAutopilotPolicy.shouldAttemptRepair(trigger: .dockerEvent))
    }
}
