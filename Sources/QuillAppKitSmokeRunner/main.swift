#if os(Linux)

import QuillAppKitSmoke

enum QuillAppKitSmokeFailure: Error {
    case validationFailed
}

@main
struct QuillAppKitSmokeRunner {
    @MainActor
    static func main() throws {
        guard QuillAppKitSmoke.validate() else {
            throw QuillAppKitSmokeFailure.validationFailed
        }
        print("QuillAppKitSmoke passed")
    }
}

#endif
