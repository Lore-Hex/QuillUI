# Vendored CodeEdit Source

- Upstream: https://github.com/CodeEditApp/CodeEdit.git
- Commit: cec6287a49a0a460cd7cab17f254eebc3ada828e
- License: MIT, preserved in `LICENSE.md`

QuillUI vendors this upstream app source tree so generic SwiftUI/AppKit
compatibility lowering can run without cloning CodeEdit on every CI or local
build. Keep the app source pristine; compatibility work belongs in QuillUI,
QuillKit, QuillData, or the reusable lowering and package-generation tooling.
