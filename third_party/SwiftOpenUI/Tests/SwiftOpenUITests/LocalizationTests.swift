import Foundation
import XCTest
@testable import SwiftOpenUI

final class LocalizationTests: XCTestCase {
    override func tearDown() {
        quillConfigureLocalizationForTesting(catalogURLs: nil)
        super.tearDown()
    }

    func testPluralCatalogSubstitutionUsesPositionalArguments() throws {
        let catalog = try writeCatalog("""
        {
          "sourceLanguage": "en",
          "strings": {
            "account.label.followers %lld %@": {
              "localizations": {
                "en": {
                  "stringUnit": {
                    "state": "translated",
                    "value": "%#@followers@"
                  },
                  "substitutions": {
                    "followers": {
                      "formatSpecifier": "lld",
                      "variations": {
                        "plural": {
                          "one": {
                            "stringUnit": {
                              "state": "translated",
                              "value": "%2$@ follower"
                            }
                          },
                          "other": {
                            "stringUnit": {
                              "state": "translated",
                              "value": "%2$@ followers"
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
        """)

        quillConfigureLocalizationForTesting(catalogURLs: [catalog])

        XCTAssertEqual(
            quillResolveLocalizedString("account.label.followers %lld %@", arguments: ["1", "1"]),
            "1 follower"
        )
        XCTAssertEqual(
            quillResolveLocalizedString("account.label.followers %lld %@", arguments: ["872850", "872.9K"]),
            "872.9K followers"
        )
        XCTAssertEqual(
            quillResolveLocalizedString("account.label.followers 872850 872.9K"),
            "872.9K followers"
        )
    }

    func testCatalogDoesNotFallBackToArbitraryLocale() throws {
        let catalog = try writeCatalog("""
        {
          "sourceLanguage": "en",
          "strings": {
            "API Versions": {
              "localizations": {
                "zz": {
                  "stringUnit": {
                    "state": "translated",
                    "value": "Wrong Locale"
                  }
                }
              }
            }
          }
        }
        """)

        quillConfigureLocalizationForTesting(catalogURLs: [catalog])

        XCTAssertEqual(quillResolveLocalizedString("API Versions"), "API Versions")
    }

    func testDashArgumentFallbackStillFormatsTemplateKeys() throws {
        let catalog = try writeCatalog("""
        {
          "sourceLanguage": "en",
          "strings": {
            "settings.display.font.scaling-%@": {
              "localizations": {
                "en": {
                  "stringUnit": {
                    "state": "translated",
                    "value": "Font scaling: %@"
                  }
                }
              }
            }
          }
        }
        """)

        quillConfigureLocalizationForTesting(catalogURLs: [catalog])

        XCTAssertEqual(
            quillResolveLocalizedString("settings.display.font.scaling-1.2"),
            "Font scaling: 1.2"
        )
    }

    private func writeCatalog(_ contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftOpenUILocalizationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("Localizable.xcstrings")
        try contents.data(using: .utf8)?.write(to: url)
        return url
    }
}
