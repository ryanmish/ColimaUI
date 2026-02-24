import XCTest
@testable import ColimaUI

final class LocalDomainsAutopilotPolicyTests: XCTestCase {
    func testRepairAllowedForManual() {
        XCTAssertTrue(LocalDomainsAutopilotPolicy.shouldAttemptRepair(trigger: .manual))
    }

    func testRepairNotAllowedForSettingsChange() {
        XCTAssertFalse(LocalDomainsAutopilotPolicy.shouldAttemptRepair(trigger: .settingsChange))
    }

    func testRepairNotAllowedForPeriodic() {
        XCTAssertFalse(LocalDomainsAutopilotPolicy.shouldAttemptRepair(trigger: .periodic))
    }

    func testRepairNotAllowedForDockerEvent() {
        XCTAssertFalse(LocalDomainsAutopilotPolicy.shouldAttemptRepair(trigger: .dockerEvent))
    }
}
