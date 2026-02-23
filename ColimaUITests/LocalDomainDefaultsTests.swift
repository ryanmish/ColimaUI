import XCTest
@testable import ColimaUI

final class LocalDomainDefaultsTests: XCTestCase {
    func testFixedSuffixConstant() {
        XCTAssertEqual(LocalDomainDefaults.suffix, "dev.local")
        XCTAssertEqual(LocalDomainDefaults.indexHost, "index.dev.local")
        XCTAssertEqual(LocalDomainDefaults.indexHTTPSURL, "https://index.dev.local")
        XCTAssertEqual(LocalDomainDefaults.cliVersion, "1.1.13")
    }

    func testNormalizeSuffixIgnoresInput() async {
        let service = LocalDomainService.shared
        let fromBlank = await service.normalizeSuffix("")
        let fromOther = await service.normalizeSuffix("example.local")
        XCTAssertEqual(fromBlank, LocalDomainDefaults.suffix)
        XCTAssertEqual(fromOther, LocalDomainDefaults.suffix)
    }
}
