import XCTest
@testable import Airpisode

final class RegionCatalogTests: XCTestCase {
    func testAutoRegionUsesLocaleRegion() {
        XCTAssertEqual(ConfigStore.autoRegion(for: Locale(identifier: "en_GB")), "GB")
        XCTAssertEqual(ConfigStore.autoRegion(for: Locale(identifier: "fr_FR")), "FR")
    }

    func testAutoRegionFallsBackToUSWithoutRegion() {
        XCTAssertEqual(ConfigStore.autoRegion(for: Locale(identifier: "en")), "US")
    }

    func testCatalogAlwaysIncludesCurrentRegionAndSortsByTitle() {
        let options = RegionCatalog.options(including: "JP", in: Locale(identifier: "en_US"))
        XCTAssertTrue(options.contains { $0.code == "JP" })
        XCTAssertTrue(options.contains { $0.code == "US" })
        let titles = options.map(\.title)
        XCTAssertEqual(
            titles,
            titles.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        )
        for option in options {
            XCTAssertFalse(option.title.isEmpty)
            XCTAssertTrue(option.title.contains(option.code))
        }
    }

    func testLabelCarriesTheCodeSoAmbiguousNamesStayIdentifiable() {
        let label = RegionCatalog.label(for: "FR", in: Locale(identifier: "en_US"))
        XCTAssertTrue(label.contains("FR"))
        XCTAssertFalse(label.isEmpty)
    }
}
