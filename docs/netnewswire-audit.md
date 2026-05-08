# NetNewsWire Port Audit

Initial audit date: 2026-05-08.

Upstream:

- Official site: https://netnewswire.com/
- Repository: https://github.com/Ranchero-Software/NetNewsWire
- Local audit clone: `.upstream/netnewswire`
- Audited commit: `d97acdc`
- License: MIT per the upstream GitHub repository metadata.

## Why NetNewsWire Is App Target 3

NetNewsWire is a better third target than another small SwiftUI demo because it is a real, mature desktop productivity app. It stresses:

- Dense split-view UI: sidebar tree, article timeline, article detail reader, toolbars, preferences, sheets, context menus, and keyboard navigation.
- Data and sync architecture: RSS/Atom/JSON Feed parsing, OPML import/export, local article databases, feed settings, smart feeds, and multiple account types.
- Web/content rendering: article HTML, theme CSS, reader view, link handling, favicons, and media.
- Platform bridges: AppKit, UIKit, WebKit, SafariServices, UserNotifications, CloudKit, WidgetKit, AppleScript, Sparkle, and extension targets.

This makes it a strong proof point after Enchanted and IceCubes. It should not be the first port because its AppKit surface is large, but it is exactly the kind of app QuillUI must eventually handle.

## Current Upstream Shape

Repository structure from the audit clone:

- `Mac/`: AppKit desktop app, including main window, sidebar, timeline, detail web view, preferences, scripting, extensions, and crash/error surfaces.
- `iOS/`: UIKit app.
- `Shared/`: shared app features such as article rendering, timeline, tree controllers, smart feeds, import/export, settings, resources, favicons, notifications, and widgets.
- `Modules/`: Swift package modules for reusable model/network/database/parser code.
- `Tests/`: app and module tests.

Rough source scale:

- 689 Swift files.
- 123 `AppKit` imports.
- 95 `UIKit` imports.
- 23 `SwiftUI` imports.
- 14 `WebKit` imports.
- 10 `CloudKit` imports.
- 8 `WidgetKit` imports.

The source is mostly Swift, but the actual desktop shell is AppKit-heavy rather than SwiftUI-heavy.

## Useful Modules To Reuse First

These are likely the best first reuse targets because they are already Swift packages and not tied to the AppKit main window:

- `RSParser`: feed, HTML metadata, OPML, JSON, XML, and date parsing.
- `FeedFinder`: feed discovery over web pages.
- `Articles`: article/status/author model types.
- `RSTree`: tree data structures for the feed/sidebar model.
- `RSWeb`: downloading and web helpers.
- `ArticlesDatabase`, `SyncDatabase`, `RSDatabase`: useful references for QuillData/SQLite work, but likely need compatibility work because they use `FMDatabase`/ObjC SQLite wrappers.

The first Linux experiment below checked `RSParser`, `Articles`, and `RSTree`.

## Linux Module Spike

Ran in the Lima Ubuntu VM with Swift 6.3.1:

- `Modules/RSTree`: library build succeeds on Linux. `swift test` exits with `no tests found`, but the module itself compiles and links as `libRSTree.so`.
- `Modules/Articles`: does not compile directly on Linux because it depends on `RSCore`, and `RSCore` currently imports Darwin-only/platform modules such as `os` while also compiling many AppKit/UIKit extensions.
- `Modules/RSParser`: does not compile directly on Linux for the same `RSCore` reason. Its external `Tidemark` dependency resolves and starts compiling successfully before `RSCore` stops the build.

Conclusion: direct reuse is viable for some leaf modules, but the critical parser/model stack needs either:

- an upstream-style `RSCoreLite` split containing only Foundation-safe helpers used by parser/model packages, or
- a Quill-side feed/parser core that ports the relevant NetNewsWire parser concepts without carrying the Apple UI extensions.

The second path is probably faster for the first Linux slice; the first path is better if we eventually want to share more code with upstream.

## Main Blockers

Direct whole-app compile on Linux is not realistic initially:

- The Mac target is AppKit-centric: `NSOutlineView`, `NSTableView`, custom `NSView` cells, `NSWindowController`, menus, pasteboard, scripting, and sharing services.
- Article rendering uses `WKWebView` and WebKit-specific configuration.
- Several Apple services do not exist on Linux: iCloud/CloudKit, Safari extension, WidgetKit, AppleScript, Sparkle updater, UserNotifications integration, and some sharing/account integrations.
- Build system is Xcode-first for the app, though several modules are SwiftPM packages.
- Database code uses existing SQLite/FMDatabase-style wrappers, which should inform QuillData but should not block a first Linux shell.

## QuillUI Strategy

Treat NetNewsWire as a staged product port, not a source-drop compile:

1. **Module spike:** compile low-platform modules on Linux, especially `RSParser`, `Articles`, and `RSTree`.
2. **QuillFeed core:** create a small Quill-side feed model/cache package if direct module reuse becomes too platform-coupled.
3. **Linux shell:** build a NetNewsWire-shaped three-pane reader:
   - sidebar tree
   - article timeline
   - article reader/detail view
4. **Local-first data:** support direct RSS/Atom/JSON Feed subscriptions and OPML import/export before sync accounts.
5. **Article rendering:** begin with sanitized HTML/plain text rendered through QuillUI; later evaluate GTK/WebKitGTK or an Adwaita/libadwaita web view escape hatch.
6. **QuillData pressure:** use the article/feed/account cache as a serious benchmark for QuillData's schema-native SQLite direction.

## Compatibility Strategy For AppKit-Heavy Code

NetNewsWire should push QuillUI beyond "SwiftUI source compatibility." The right goal is not a magical full AppKit-to-SwiftUI converter. A complete automatic conversion of arbitrary `NSViewController`, `NSTableView`, `NSOutlineView`, responder-chain, target/action, xib/storyboard, pasteboard, and `WKWebView` code would be brittle and would hide too many behavior changes.

The useful approach is a three-layer compatibility system:

1. **QuillUI controls for SwiftUI-shaped ports.**
   - Build first-class reusable controls for the patterns NetNewsWire needs: `QuillSplitView`, `QuillSidebarList`, `QuillOutlineList`, `QuillTable`, `QuillToolbar`, `QuillInspector`, `QuillSearchField`, `QuillStatusBar`, `QuillWebContentView`, and menu/command helpers.
   - These should look native on Linux and should also compile on macOS via SwiftUI.

2. **QuillKit/AppKit-shaped adapters for old code.**
   - Provide small compatibility types where they reduce porting cost: `NSPasteboard`-like clipboard API, `NSEvent`-like keyboard descriptors, `NSMenu`/command models, `NSToolbar`-style toolbar items, table/outline selection models, and URL-opening/sharing abstractions.
   - Avoid implementing a fake complete AppKit. Implement the contracts that real apps keep needing, backed by GTK/libadwaita/WebKitGTK where possible.

3. **A SwiftSyntax migration assistant, not an invisible runtime converter.**
   - Build a `quill-migrate` tool that scans AppKit code and emits QuillUI skeletons for common patterns:
     - `NSViewController` -> `View`
     - `NSTableViewDataSource`/`NSTableViewDelegate` -> `QuillTable`
     - `NSOutlineViewDataSource`/delegate -> `QuillOutlineList`
     - `NSMenuItem`/`@IBAction` -> command/action closures
     - `WKWebView` setup -> `QuillWebContentView`
   - The generated code should be editable Swift, with diagnostics and TODOs for unsupported behavior.

This lets QuillUI support more of NetNewsWire's old architecture without pretending that AppKit source can run unchanged on Linux.

## Coverage Areas NetNewsWire Should Force

NetNewsWire is valuable because it gives QuillUI a concrete compatibility checklist:

- Three-pane desktop layout with persistent column widths.
- Large virtualized article lists with selection, unread/starred state, context menus, and keyboard navigation.
- Tree/sidebar model with disclosure, drag/reorder later, unread badges, and smart-feed sections.
- Toolbar and menu command routing.
- Search field and filtering.
- Local SQLite article/feed cache via QuillData.
- OPML import/export.
- Clipboard, URL opening, and share/send abstractions.
- Web/article rendering via sanitized fallback first, then WebKitGTK or Adwaita escape hatch.
- Preferences/settings surfaces.
- Background refresh and progress/error reporting.

If QuillUI covers this list, it becomes a credible compatibility layer for a large class of mature Mac desktop apps, not just new SwiftUI apps.

## First Linux Milestone

`quill-netnewswire-slice`:

- Load a small OPML/default feed list.
- Fetch and parse feeds using reused NetNewsWire parser code where possible.
- Persist feed and article summaries locally.
- Render a three-pane GTK desktop shell via QuillUI.
- Support read/unread/starred local state.
- Cover parser/cache behavior with tests and include a Linux Xvfb smoke screenshot.

## Not In The First Milestone

- iCloud/CloudKit sync.
- Feedbin/Feedly/Inoreader/NewsBlur/FreshRSS account parity.
- Safari extension.
- WidgetKit.
- AppleScript.
- Sparkle update flow.
- Full custom article themes.
- Full `WKWebView` behavior.
