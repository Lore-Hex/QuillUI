# Apple and Package Function Coverage

This ledger tracks the Apple-framework compatibility packages and app-facing
package clones exposed by QuillUI on Linux. It is source-inspected from the
current repository, not yet a generated ABI diff against Apple SDKs or upstream
third-party packages. APIs not listed here should be treated as incomplete on
Linux until a source-contract test or implementation row is added.

Function rows group equivalent overloads or property-only accessors when they
share the same behavior. "Complete" means complete for QuillUI's current tested
contract, not complete Apple SDK parity.

For triage purposes, `Usable` and `Parity` rows are complete for today's tested
Linux contract. `Partial`, `Fallback`, `Compile-only`, and `Incomplete` rows are
still incomplete until the missing behavior is implemented and covered by
source-contract, golden, or fuzz tests.

Status ladder:

- `Compile-only`: the import, type, or call compiles, but runtime behavior is a
  placeholder.
- `Fallback`: the call has deterministic fallback behavior, usually recording a
  compatibility diagnostic, but it does not perform the native OS side effect.
- `Partial`: a real subset works, with documented gaps.
- `Usable`: enough runtime behavior exists for current app workflows and tests.
- `Parity`: above Usable. The same source compiles and runs on Apple and Linux,
  deterministic APIs produce the same outputs under golden and seeded fuzz
  tests, UI flows have backend-equivalent behavior and rendering, and any
  unavoidable OS differences are explicit.

A `Parity` row is intentionally narrow: it means the named function or value
contract has Apple/Linux tests, not that the whole framework is complete.

## Package Summary

Use this table to find the detailed package section below. The per-function
rows remain the source of truth: a function is complete today only when its row
is `Usable` or `Parity`.

| Apple package | Complete function rows today | Incomplete function rows and parity blockers |
| --- | --- | --- |
| `SwiftUI` clone layer | `Font.Weight`. | Module boundary and app-facing view/modifier metadata paths are partial; baseline alignments fallback; full layout, diffing, animation, transition, gesture, accessibility, focus, scene, and rendering behavior is incomplete. |
| `SwiftData` / `QuillData` | `QuillTableMappable` table/name/convert/update helpers, `ModelContext.insert`, `delete`, `save`, and `QuillDataError.description`. | Database scalar conversion, fetches, predicates, configuration, schemas, containers, sorting, and macros are partial or compile-only; migrations, relationships, undo, CloudKit, constraints, predicate lowering, and concurrency are incomplete. |
| `AppKit` / `QuillAppKit` | Undo execution and registration gates, `NSStringFromRect`, view hierarchy and geometry mutation, child-controller links, window geometry mutation, pasteboard string/data/item storage, menu item models, arranged stack subviews, progress value mutation, pop-up item selection, and selected singleton/property flows. | Most native OS behavior is partial, fallback, compile-only, or incomplete: event loop and dispatch, focus, dialogs, window manager integration, Auto Layout, drawing/layers, accessibility, cursor/event taps, native menus, drag/drop, text layout, document architecture, SwiftUI hosting, status items, popovers, visual effects, animation timing, haptics, sharing, audio, XPC, font discovery, file icons, and workspace services. |
| `UIKit` / `QuillUIKit` | `UIApplication.shared`. | Aliases, app opening, device metadata, pasteboard, views, hierarchy, and notifications are partial/fallback; constraints, scenes, controllers, navigation, split views, collections, alerts, controls, labels/images/key commands, renderer, lifecycle, layout, events, accessibility, and text input are incomplete. |
| `WebKit` | None yet beyond compile-compatible shapes. | `WKWebView`, configuration, delegates, user scripts, content rules, navigation, HTML rendering, JavaScript, process isolation, and scheme handling are compile-only or incomplete. |
| `AuthenticationServices` | None yet beyond compile-compatible shapes. | Web authentication session start is fallback; session cancellation, presentation anchors, callback handling, secure storage, and browser flow parity are incomplete. |
| `UniformTypeIdentifiers` | App-facing known extension lookup, conforming known extension lookup, common static types, local conformance checks, and preferred extension/MIME metadata for known identifiers. | Identifier parsing remains partial; system registry lookup, dynamic/exported/imported types, tag classes, synthesized dynamic identifiers for unknown extensions, and the full conformance graph need parity work. |
| `Network` | `IPv4Address`, `IPv6Address`, `NWPathMonitor` initial `currentPath` and pre-start `cancel()`, `NWPath.Status`, `NWPath.UnsatisfiedReason`, `NWPath.supportsIPv4`, `NWPath.supportsIPv6`, `NWPath.supportsDNS`, `NWPath.usesInterfaceType(_:)`, `NWInterface.InterfaceType`, `NWInterface` values returned by scoped address/host parsing, `NWEndpoint.Port` parsing/known constants/properties/debug text/equality/hash behavior, scoped and unscoped `NWEndpoint.Host.init(_:)` classification/description/equality/hash behavior, common `NWEndpoint` host-port/service/Unix path value descriptions, equality, hashing, `NWError.posix(_:)`, `.dns(_:)`, `.tls(_:)`, equality, debug/describing/reflecting/localized text, `NWProtocolTCP.Options` constructor/default/getter/setter surface, `NWProtocolUDP.Options.preferNoChecksum`, `NWProtocolTLS.Options`, `NWProtocolOptions`, `NWParameters.defaultProtocolStack`, `NWParameters.ProtocolStack`, `NWProtocolIP.Options`, IP option enums, `NWParameters.tcp`, `.udp`, `.tls`, `.dtls`, `NWParameters.init(tls:tcp:)`, `init(dtls:udp:)`, `NWParameters.Attribution`, `ExpiredDNSBehavior`, `MultipathServiceType`, `ServiceClass`, parameter policy setters/defaults, and `NWParameters` debug/string text now have Apple-checked `Parity` rows for current tested contracts. `NWPathMonitor.start(queue:)` is `Usable` for a Linux one-shot current-interface snapshot. `NetworkPathInterfaceParityTests` pins the path monitor pre-start state, pre-start cancel state, path helper-query results, path/interface enum string, resolved scoped interface value, Linux start snapshot consistency, equality, and hash contracts. `NetworkIPAddressParityTests` captures the IPv4/IPv6 parser, legacy IPv4 single-component wrapping, dotted octal/hex IPv4 edge cases, data length, classifier-boundary, multicast-scope, IPv4 mapping, empty/unresolved IPv6 scope fallback, string, debug-output, address equality/hash, and `IPv6Address.Scope` raw-value edge matrix observed on Apple Network. `NetworkEndpointPortParityTests` now covers port parser, constant, equality, and hash semantics. `NetworkEndpointHostParityTests` now covers scoped parsed-to-direct host equality/hash, empty/unresolved/malformed scope fallback classification, scoped host-port endpoint equality/hash, and endpoint value text. `NetworkErrorParityTests` covers `NWError` Sendable/Equatable value surface, POSIX/DNS/TLS payload text, Apple localizedDescription formatting, and the intentionally non-Hashable protocol shape. `NetworkParametersParityTests` covers parameter and protocol option constructor/value text, TCP Bool/Int option defaults and setters, UDP checksum-preference defaults and setters, fresh reference identity, Sendable surface, protocol-stack/default-stack/IP option value surfaces, policy enum text, defaults, setter normalization, local endpoint debug formatting, and Apple-matched traffic/multipath/proxy/DNSSEC debug segments. | Continuous live path monitoring, exact Apple path/DNS policy flags, synthetic constructed interfaces, connections, listeners, DNS/TLS transport behavior, UDP/TCP socket behavior, IP packet/socket option effects, and NetworkExtension VPN behavior are incomplete or fallback-only. |
| `NetworkExtension` | None yet beyond compile/fallback shapes. | Packet flow, VPN lifecycle, tunnel routing, provider hosting, and real tunnel settings are incomplete. |
| `CoreGraphics` | None yet beyond compile/fallback shapes. | Event sources, key state, keyboard events, event posting, pointer events, event taps, and drawing APIs beyond shared geometry are incomplete. |
| `Security` | None yet at `Usable`; certificate wrapping is partial and trust calls fallback. | Keychain, certificate parsing, policy evaluation, platform trust store, and Secure Transport parity are incomplete. |
| `AVFoundation` / `AVKit` | None yet beyond compile/fallback shapes. | Speech synthesis, audio session, playback, audio engine graph processing, taps, buffers, formats, video rendering, media decoding, capture, and real media I/O are incomplete. |
| `Speech` | None yet beyond compile/fallback shapes. | Authorization, recognizer availability, recognition tasks, audio transcription, and audio bridge behavior are incomplete. |
| `PhotosUI` / `Photos` | None yet beyond compile-compatible shapes. | Photo-library authorization, asset fetching, picker UI, transferable item loading, and photo service behavior are incomplete. |
| `Charts`, `StoreKit`, `TipKit` | None yet beyond compile-compatible shapes. | Chart marks/rendering/axes/scales/interaction/accessibility, product lookup, purchases, transactions, subscriptions, tip rules, persistence, display frequency, and popovers are incomplete. |
| `Observation` | None yet at `Usable`; `@Observable` lowering is partial. | Tracking, invalidation, access lists, registrar behavior, and observation parity are incomplete. |
| `ApplicationServices` | None yet at `Usable`; process trust check is partial. | Accessibility tree inspection, mutation, notifications, app targeting, and attribute access are incomplete. |
| `ServiceManagement` | `SMAppService.register()` and `unregister()`. | Main-app/status behavior is partial; login item parity, privileged helpers, and platform service managers are incomplete. |
| `AsyncAlgorithms` | `AsyncTimerSequence.init(interval:clock:)` and iterator `next()`. | Other AsyncAlgorithms package algorithms are incomplete. |
| `Carbon` | None yet beyond compile-compatible shapes. | Hot-key registration, event targets, and classic Carbon APIs are incomplete. |
| `Combine` | `AnyPublisher.init()` where `Failure == Never`. | OpenCombine coverage, merge behavior, backpressure, schedulers, demand, cancellation, operators, and seeded edge-case parity remain partial or incomplete. |
| `os` | `Logger.init(...)`. | Logging calls, `os_log`, dyld inspection, unfair-lock semantics, signposts, persistence, and tooling parity are partial, compile-only, or incomplete. |
| `IOKit` | None yet beyond compile/fallback shapes. | USB/device discovery, notifications, registry traversal, matching, iterators, and object lifetime behavior are incomplete. |
| Re-export-only Apple shims | Imports compile for current app source. | `MessageUI`, `SafariServices`, `MobileCoreServices`, `LocalAuthentication`, and `CoreSpotlight` do not implement standalone framework behavior yet. |

## SwiftUI

Linux `SwiftUI` re-exports `SwiftOpenUI` plus local compatibility extensions.
The upstream `SwiftOpenUI` surface is not exhaustively duplicated here; this
table covers the local Apple-package clone layer.

| API or function | Linux status | Notes |
| --- | --- | --- |
| `import SwiftUI` | Partial | Resolves to `SwiftOpenUI` plus `QuillSwiftUICompatibility`; it intentionally does not ambiently re-export `QuillUI` to avoid AppKit symbol collisions. |
| `Font.Weight` | Usable | Local typealias to `FontWeight`; enough for app source compatibility. |
| `VerticalAlignment.firstTextBaseline` | Fallback | Maps to `.top`; true text-baseline metrics are incomplete. |
| `VerticalAlignment.lastTextBaseline` | Fallback | Maps to `.bottom`; true text-baseline metrics are incomplete. |
| Common view declarations, modifiers, focus wrappers, menu/picker/list metadata | Partial | Covered through `SwiftOpenUI`, QuillUI metadata, and focused source-contract tests. |
| Layout, diffing, animation, transition, gesture, accessibility, focus routing, multi-window semantics | Incomplete | These are the main blockers between Usable and Parity. |

## SwiftData

The Linux `SwiftData` product re-exports `QuillData`.

| API or function | Linux status | Notes |
| --- | --- | --- |
| `PersistentModel.databaseValue` | Partial | Converts supported scalar and Codable values for SQLite persistence. |
| `PersistentModel.fromDatabaseValue(_:)` | Partial | Supports current database-backed model value decoding paths. |
| `PersistentModel.decode(from:)` | Partial | Codable-backed decode helper, not full SwiftData materialization parity. |
| `Array.databaseValue` and `Array.fromDatabaseValue(_:)` | Partial | Codable array conversion for supported stored values. |
| `QuillTableMappable.createTableSQL` | Usable | Implemented for macro-generated table models. |
| `QuillTableMappable.tableName` | Usable | Stable name support exists for current generated models. |
| `QuillTableMappable.toTableStruct()` | Usable | Used by persistence bridge. |
| `QuillTableMappable.update(from:)` | Usable | Used by persistence bridge. |
| `QuillTableMappable.fromTableStruct(_:)` | Usable | Used by persistence bridge. |
| `QuillTableMappable.fetchPersistentModels(_:sql:)` | Partial | SQLite-backed fetch path, not full SwiftData query behavior. |
| `@Attribute` | Compile-only | Macro spelling exists; option behavior is narrow. |
| `@Relationship` | Compile-only | Relationship spelling exists; relationship graph behavior is incomplete. |
| `@QuillModel` | Partial | Generates current model/table bridge, not full `@Model` parity. |
| `#QuillPredicate` | Partial | Supports current SQL-filter path, not full Swift predicate translation. |
| `AttributeOption` | Compile-only | Selected option names compile; full semantics are incomplete. |
| `RelationshipOption.deleteRule(_:)` | Compile-only | Spelling exists; full relationship/delete-rule semantics are incomplete. |
| `Schema.init(_:)` | Partial | Records model types for current container setup. |
| `ModelContainer.init(for:configurations:)` | Partial | Creates current SQLite/in-memory container paths. |
| `ModelActor` | Compile-only | Protocol spelling exists; full actor/executor isolation parity is incomplete. |
| `ModelExecutor.init(modelContext:)` | Compile-only | Stores context for current code shape. |
| `DefaultSerialModelExecutor` | Compile-only | Shape exists; full SwiftData executor semantics are incomplete. |
| `FetchDescriptor.init(predicate:sortBy:fetchLimit:)` | Partial | Supports current fetch input shape. |
| `FetchDescriptor.init(filter:sortBy:fetchLimit:)` | Partial | Supports current SQL filter path. |
| `Predicate.init(_:)` | Partial | In-memory predicate closure path. |
| `Predicate.init(sqlFilter:_:)` | Partial | SQL-filter carrier for current persistence bridge. |
| `Predicate.evaluate(_:)` | Partial | Evaluates closure predicates only. |
| `ModelConfiguration.init(schema:url:isStoredInMemoryOnly:)` | Partial | Current URL and in-memory flags are honored where the bridge supports them. |
| `QuillDataError.description` | Usable | Deterministic error text. |
| `ModelContext.init(_:)` | Partial | Current context setup works for supported containers. |
| `ModelContext.insert(_:)` | Usable | Works for supported persistent models. |
| `ModelContext.fetch(_:)` | Partial | Works for supported descriptors and table models. |
| `ModelContext.delete(_:)` | Usable | Works for supported persistent models. |
| `ModelContext.delete(model:where:)` | Partial | SQL-filter delete path only. |
| `ModelContext.save()` | Usable | Commits current context changes. |
| `SortDescriptor.init(_:order:)` | Partial | Stores key-path/order metadata for supported fetches. |
| SQLite snapshot helpers | Compile-only | Present as zero/no-op stubs. |
| Migrations, relationships, undo, CloudKit, rich schema constraints, full predicate lowering | Incomplete | Required for SwiftData Parity. |

## AppKit

The Linux `AppKit` product is backed by `QuillAppKit`. It is the broadest
Apple shim and mixes usable in-memory widget behavior with compile-only
platform fallbacks.

| API or function | Linux status | Notes |
| --- | --- | --- |
| `UndoManager.registerUndo(withTarget:handler:)` | Usable | In-memory undo stack for current app code. |
| `UndoManager.beginUndoGrouping()` / `endUndoGrouping()` | Partial | Basic grouping exists; full AppKit undo grouping behavior is incomplete. |
| `UndoManager.undo()` / `redo()` | Usable | Executes stored closures. |
| `UndoManager.removeAllActions()` / `removeAllActions(withTarget:)` | Partial | Clears current stored closures, not full target/selector semantics. |
| `UndoManager.setActionName(_:)` | Partial | Stores action metadata only. |
| `UndoManager.disableUndoRegistration()` / `enableUndoRegistration()` | Usable | Gates current closure registration. |
| `NSStringFromRect(_:)` | Usable | Re-exported from Foundation through `QuillFoundation`; deterministic rect text is smoke-tested through the AppKit smoke target. |
| `NSRectFromString(_:)` | Partial | Re-exported from Foundation through `QuillFoundation`; common AppKit rect strings and `NSStringFromRect` round-trips are covered, while full Apple parser edge-case/fuzz parity is still pending. |
| `NSBitmapImageRep.init?(data:)` / `representation(using:properties:)` | Partial | Basic data wrapping, not full image codec parity. |
| `NSFontManager.availableFonts()` / `availableFontFamilies()` | Partial | Returns deterministic fallback Mac-shaped font and family names for source compatibility; no host font discovery or metrics yet. |
| `NSFontManager.availableMembers(ofFontFamily:)` | Partial | Returns deterministic member rows for fallback families and `nil` for unknown families; trait values are compatibility placeholders. |
| `NSAppearance.init(named:)` / `bestMatch(from:)` | Partial | Named appearances retain their names, high-contrast constants use deterministic Apple-shaped raw values, and common light/dark/vibrant best-match fallbacks are smoke-tested. Full system appearance resolution remains incomplete. |
| `NSResponder` mouse/key/touch handlers | Fallback | Forwarding/no-op behavior only. |
| `NSResponder.becomeFirstResponder()` / `resignFirstResponder()` | Fallback | Returns true without native focus system. |
| `NSView.init(frame:)` | Usable | Stores frame and bounds. |
| `NSView.addSubview(_:)` / positioned add | Usable | Maintains in-memory hierarchy. |
| `NSView.removeFromSuperview()` | Usable | Updates in-memory hierarchy. |
| `NSView.setFrameSize(_:)` / `setFrameOrigin(_:)` | Usable | Updates in-memory geometry. |
| `NSView.layoutSubtreeIfNeeded()` / display invalidation calls | Fallback | Marks simple flags; no native layout/render pass. |
| `NSView.convert(_:from:)` / `convert(_:to:)` | Partial | Basic coordinate conversion only. |
| `NSView.hitTest(_:)` | Partial | In-memory bounds/subview hit testing. |
| `NSView.addTrackingArea(_:)` / `removeTrackingArea(_:)` | Partial | Tracks registered areas without native event delivery. |
| `NSViewController.loadView()` / lifecycle hooks | Fallback | Hook shape exists; no platform lifecycle. |
| `NSViewController.addChild(_:)` / `removeFromParent()` | Usable | Maintains child relationships. |
| `NSViewController.presentAsSheet(_:)` / `presentAsModalWindow(_:)` / `dismiss(_:)` | Fallback | Presentation state only. |
| `NSWindow.init(...)` | Usable | Stores content, frame, style, and state. |
| `NSWindow.makeKeyAndOrderFront(_:)` / `orderFront(_:)` / `orderOut(_:)` | Partial | Updates visibility/key state without native window manager. |
| `NSWindow.close()` / `performClose(_:)` | Partial | Updates state and notifications used by tests. |
| `NSWindow.miniaturize(_:)` / `deminiaturize(_:)` / `zoom(_:)` | Fallback | State/no-op behavior only. |
| `NSWindow.toggleFullScreen(_:)` | Compile-only | No-op. |
| `NSWindow.setFrame(...)`, `setFrameOrigin(_:)`, `setContentSize(_:)` | Usable | Updates stored geometry. |
| `NSWindow.center()` | Compile-only | No-op. |
| `NSWindow.makeFirstResponder(_:)` | Partial | Stores responder without native focus routing. |
| `NSWindow.setFrameAutosaveName(_:)` / `saveFrame(usingName:)` / `setFrameUsingName(_:)` | Compile-only | Autosave is not implemented. |
| `NSWindow.registerForDraggedTypes(_:)` | Compile-only | No native drag registration. |
| `NSPanel` initializers and properties | Partial | Property bag over `NSWindow`. |
| `NSApplication.shared` | Usable | Singleton app object. |
| `NSApplication.setActivationPolicy(_:)` / `activate(...)` / `deactivate()` | Fallback | Records state only. |
| `NSApplication.run()` / `stop(_:)` | Fallback | Hook/no-op loop, not a native event loop. |
| `NSApplication.sendEvent(_:)` / `nextEvent(...)` | Compile-only | Event dispatch is incomplete. |
| `NSApplication.beginModalSession(...)`, `runModal(...)`, sheet helpers | Fallback | Modal state only. |
| `NSApplication.sendAction(...)` | Partial | Basic target/action bridge only. |
| `NSDockTile.display()` | Compile-only | No-op. |
| `NSEvent.addLocalMonitorForEvents(...)` / global monitor helpers | Compile-only | No real OS event taps. |
| `NSPasteboard.clearContents()` | Usable | Clears in-memory pasteboard. |
| `NSPasteboard.setString(_:forType:)` / `string(forType:)` | Usable | In-memory string storage. |
| `NSPasteboard.setData(_:forType:)` / `data(forType:)` | Usable | In-memory data storage. |
| `NSPasteboard.writeObjects(_:)` / `readObjects(...)` | Partial | Current pasteboard item paths only. |
| `NSPasteboardItem.setString`, `setData`, `setPropertyList` and getters | Usable | In-memory item storage. |
| `NSWorkspace.open(_:)` and overloads | Fallback | Delegates where host support exists, otherwise records diagnostic/no-op. |
| `NSWorkspace.selectFile`, `activateFileViewerSelecting` | Fallback | Opens containing directories through `xdg-open` when a Linux desktop session is available; records diagnostics and no-ops in headless environments. |
| `NSWorkspace.icon(forFile:)`, `icon(forContentType:)` | Fallback | Returns deterministic 32x32 placeholders with diagnostics; desktop icon lookup is not implemented yet. |
| `NSWorkspace.urlForApplication(...)` | Partial | Uses `xdg-mime` plus XDG application directories for existing `.desktop` files; bundle identifiers only resolve when they already map to a Linux desktop entry. |
| `NSCursor.push()` / `pop()` / `set()` / hide helpers | Compile-only | No native cursor effects. |
| `NSMenu.addItem(_:)`, `insertItem`, `removeItem`, `item(at:)` | Usable | In-memory menu model. |
| `NSMenu.popUp(...)`, `update()`, `cancelTracking()` | Fallback | No native menu display. |
| `NSMenuItem.init(...)` / `separator()` | Usable | Stores title/action/key equivalent metadata. |
| `NSToolbar.insertItem(withItemIdentifier:at:)` / `removeItem(at:)` / `validateVisibleItems()` | Partial | In-memory toolbar item list only. |
| `NSAlert.addButton(withTitle:)`, `runModal()`, `beginSheetModal(...)` | Fallback | Deterministic modal response, no native dialog. |
| `NSSavePanel.runModal()` / `begin(...)` / `beginSheetModal(...)` | Fallback | Returns `.OK` and completes synchronously; real file dialog is incomplete. |
| `NSOpenPanel` configuration / `runModal()` / `begin(...)` / `beginSheetModal(...)` | Fallback | Stores picker configuration and deterministically returns `.cancel`; no native dialog or user selection yet. |
| `NSScrollView` document-view helpers and `flashScrollers()` | Partial | Stores document view; no native scrolling. |
| `NSTextField` convenience constructors | Partial | Create label/text-field property containers. |
| `NSTextView.setSelectedRange(_:)`, `replaceCharacters`, `insertText` | Partial | In-memory text mutation only. |
| `NSTextView.scrollRangeToVisible(_:)` | Compile-only | No-op. |
| `NSTextStorage.addLayoutManager(_:)` / `removeLayoutManager(_:)` | Compile-only | No text layout engine. |
| `NSLayoutManager.addTextContainer(_:)` | Partial | Stores container metadata only. |
| `NSControl.sendAction(_:)`, `sizeToFit()` | Partial | Action/property behavior only. |
| `NSButton.setButtonType(_:)`, radio/checkbox constructors | Partial | Stores button state, no native widget. |
| `NSSlider` initializers and value configuration | Partial | Property bag only. |
| `NSStackView.addArrangedSubview`, `insertArrangedSubview`, `removeArrangedSubview` | Usable | Maintains arranged subview list. |
| `NSProgressIndicator.startAnimation(_:)` / `stopAnimation(_:)` | Fallback | Updates animation state only. |
| `NSProgressIndicator.increment(by:)` | Usable | Updates stored double value. |
| `NSPopUpButton.addItem`, `addItems`, select/remove/item lookup helpers | Usable | In-memory item selection model. |
| `NSSplitView.addArrangedSubview`, `insertArrangedSubview`, `removeArrangedSubview`, `setPosition`, `adjustSubviews` | Partial | Stores panes/positions without native layout. |
| `NSSplitViewController.addSplitViewItem`, `insertSplitViewItem`, `removeSplitViewItem` | Partial | Maintains controller list. |
| `NSTableView.reloadData`, row/column mutation, selection helpers | Partial | In-memory table bookkeeping, no native cell lifecycle parity. |
| `NSTableView.makeView`, `view(atColumn:row:)`, `rowView(atRow:makeIfNecessary:)` | Compile-only | Returns stored/empty views only where available. |
| `NSOutlineView.reloadItem`, expand/collapse, item/row lookup helpers | Partial | In-memory outline state; full delegate/data-source parity is incomplete. |
| `NSDocument` initializers and file/window-controller helpers | Partial | Stores document metadata; real document architecture is incomplete. |
| `NSDocumentController.openDocument(...)`, `newDocument(...)`, document add/remove | Partial | Current callback shape exists; real app document flow is incomplete. |
| `NSHostingView` / `NSHostingController` initializers | Partial | Holds root view for source compatibility; full SwiftUI hosting parity is incomplete. |
| `NSViewRepresentable` / `NSViewControllerRepresentable` context types | Compile-only | Protocol shape exists for current source lowering. |
| `NSStatusBar.statusItem(withLength:)` / `removeStatusItem(_:)` | Partial | In-memory status item model only. |
| `NSPopover.show(...)`, `performClose(_:)`, `close()` | Fallback | Visibility state only. |
| `NSVisualEffectView` / `NSBox` initializers and properties | Compile-only | Property containers; no visual effects. |
| `NSAnimationContext.runAnimationGroup(...)` | Fallback | Runs closure immediately. |
| `NSHapticFeedbackManager.perform(...)` | Fallback | No haptic hardware effect. |
| `NSSharingService.perform(withItems:)` / `sharingServices(forItems:)` | Compile-only | Sharing integration is absent. |
| `NSSound.play()` / `stop()` / `NSBeep()` | Fallback | No native audio playback. |
| `NSXPCConnection.resume()` / `suspend()` / `invalidate()` / `remoteObjectProxy()` | Compile-only | XPC is not implemented. |
| `NSHumanReadableCopyright()`, `NSFullUserName()`, `NSFindPanelAction()` | Fallback | Deterministic helper values only. |

## UIKit

The Linux `UIKit` product combines `UIKitShim` with `QuillUIKit`.

| API or function | Linux status | Notes |
| --- | --- | --- |
| `UIImage`, `UIColor`, `UIFont`, `UIScreen` aliases | Partial | Map to AppKit types when importable, otherwise to QuillFoundation fallbacks. |
| `UIApplication.shared` | Usable | Singleton shape exists. |
| `UIApplication.open(_:options:completionHandler:)` | Partial | Uses `NSWorkspace` when AppKit is available; otherwise completion is `false`. |
| `UIApplication.registerForRemoteNotifications()` | Compile-only | No-op. |
| `UIApplication.setAlternateIconName(_:completionHandler:)` | Fallback | Calls completion with nil, no icon change. |
| `UIApplication.connectedScenes`, `applicationState`, `alternateIconName` | Compile-only | Static/default metadata only. |
| `UIScene.delegate` | Compile-only | Property only. |
| `UIImpactFeedbackGenerator.prepare()` / `impactOccurred(...)` | Fallback | Records diagnostics, no haptics. |
| `UISelectionFeedbackGenerator.prepare()` / `selectionChanged()` | Fallback | Records diagnostics, no haptics. |
| `UINotificationFeedbackGenerator.prepare()` / `notificationOccurred(_:)` | Fallback | Records diagnostics, no haptics. |
| `UIDevice.current`, `name`, `userInterfaceIdiom` | Partial | Host-name and `.mac` style metadata. |
| `NSLayoutDimension.constraint(equalToConstant:)` | Compile-only | Constraint object shape only. |
| `NSLayoutConstraint.activate(_:)` | Compile-only | No layout solver. |
| `UIView.init(frame:)` | Partial | Stores frame and common view metadata. |
| `UIView.addSubview(_:)` / `removeFromSuperview()` | Partial | Current hierarchy bookkeeping only. |
| `UIView.setNeedsLayout()` / `layoutIfNeeded()` | Fallback | No native UIKit layout engine. |
| `UIView.animate(...)` overloads | Fallback | Runs animation closure immediately, then completion. |
| `UIViewController.present(...)` / `dismiss(...)` | Compile-only | No native presentation. |
| `UINavigationController.pushViewController`, `popViewController` | Compile-only | No real navigation stack behavior. |
| `UISplitViewController.show(...)` | Compile-only | No real split-view presentation. |
| `UICollectionView.cellForItem(at:)` | Compile-only | Returns nil. |
| `UIAlertController.addAction(_:)` | Compile-only | No real alert action handling. |
| `UIPasteboard.general` string/data helpers | Partial | In-memory pasteboard bridge. |
| `UIControl.setTitle(_:for:)` and value/action helpers | Compile-only | Property shape only. |
| `UIImageView`, `UILabel`, `UIKeyCommand` initializers | Compile-only | Source compatibility only. |
| `UNUserNotificationCenter.requestAuthorization(...)` | Fallback | Callback shape exists; no platform notification registration. |
| UIKit layout engine, rendering, event delivery, accessibility, text input, collection/table data-source parity | Incomplete | Required for UIKit Parity. |

## WebKit

The Linux `WebKit` product re-exports `QuillShims`; WebKit behavior is in
`QuillWebKit`.

| API or function | Linux status | Notes |
| --- | --- | --- |
| `WKWebView.init()` / `init(frame:configuration:)` / `init(coder:)` | Compile-only | Creates object/configuration shape. |
| `WKWebView.loadFileURL(_:allowingReadAccessTo:)` | Compile-only | No-op. |
| `WKWebView.load(_:)` | Compile-only | Returns nil; no navigation. |
| `WKWebView.loadHTMLString(_:baseURL:)` | Compile-only | Returns nil; no rendering. |
| `WKWebView.reload()` / `stopLoading()` | Compile-only | No-op. |
| `WKWebView.evaluateJavaScript(_:)` | Compile-only | Async returns nil. |
| `WKUserContentController.addUserScript`, `add(_:)`, `removeAllUserScripts()` | Compile-only | No script injection. |
| `WKWebViewConfiguration.setURLSchemeHandler(_:forURLScheme:)` | Compile-only | No scheme handling. |
| `WKContentRuleListStore.default()` / `compileContentRuleList(...)` | Compile-only | Returns nil rule list. |
| `WKNavigationDelegate.webView(_:didFinish:)` | Compile-only | Protocol shape only. |
| `WKNavigationAction.request`, `WKNavigationActionPolicy`, preferences, webpage preferences | Compile-only | Metadata/property shapes only. |
| HTML rendering, navigation, JavaScript execution, process isolation, content rules | Incomplete | Required for WebKit Parity. |

## AuthenticationServices

The Linux `AuthenticationServices` product re-exports `QuillShims`; the usable
subset lives in `QuillUIKit`.

| API or function | Linux status | Notes |
| --- | --- | --- |
| `ASWebAuthenticationSession.init(url:callbackURLScheme:completionHandler:)` | Compile-only | Stores shape only; callback is not driven by a browser flow. |
| `ASWebAuthenticationSession.start()` | Fallback | Returns true without performing authentication. |
| `ASWebAuthenticationSession.cancel()` | Compile-only | No-op. |
| `ASWebAuthenticationPresentationContextProviding.presentationAnchor(for:)` | Compile-only | Protocol shape only. |
| Real browser authentication, callback URL handling, secure session storage | Incomplete | Required for AuthenticationServices Parity. |

## UniformTypeIdentifiers

| API or function | Linux status | Notes |
| --- | --- | --- |
| `UTType.init?(_:)` | Partial | Accepts non-empty identifiers after trimming. |
| `UTType.init?(filenameExtension:)` | Usable | Maps the current app-facing known extension set case-insensitively, including common image aliases. Unknown-extension dynamic type synthesis is incomplete. |
| `UTType.init?(filenameExtension:conformingTo:)` | Usable | Filters known extension lookups through the local conformance graph, matching file-importer and item-provider selection needs. Unknown or nonmatching dynamic type synthesis is incomplete. |
| `UTType.conforms(to:)` | Usable | Covers the current app-facing parent graph for text, data, images, audio, movie, URL, directory, and PDF identifiers. |
| `UTType.preferredFilenameExtension` | Usable | Returns deterministic preferred extensions for known app-facing identifiers. |
| `UTType.preferredMIMEType` | Usable | Returns deterministic MIME types for known app-facing identifiers where the Apple API would expose one. |
| `UTType.localizedDescription` | Usable | Returns deterministic English descriptions for known identifiers. |
| Static UTTypes such as `.item`, `.content`, `.data`, `.text`, `.plainText`, `.json`, `.image`, `.png`, `.jpeg`, `.tiff`, `.gif`, `.heic`, `.heif`, `.webP`, `.movie`, `.audio`, `.pdf` | Usable | Current common identifiers exist for app source compatibility and file-selection tests. |
| System registry lookup, dynamic/exported/imported types, tag classes, synthesized dynamic identifiers, full conformance graph | Incomplete | Required for UTType Parity. |

## Network

| API or function | Linux status | Notes |
| --- | --- | --- |
| `NWPathMonitor.init()` / `init(requiredInterfaceType:)` / pre-start `currentPath` | Parity | Apple-checked constructor shape and initial `currentPath` for the default monitor and every required `NWInterface.InterfaceType` filter: status `unsatisfied`, reason `notAvailable`, no interfaces, not expensive, not constrained, no IPv4/IPv6/DNS support, and no used interface type. `NetworkPathInterfaceParityTests` runs the same contract on Apple Network and the Linux shim. Live path updates remain covered by `start(queue:)` and are not parity. |
| `NWPathMonitor.cancel()` before `start(queue:)` | Parity | Apple-checked pre-start cancellation is non-throwing and preserves the same initial `currentPath` for the default monitor and every required interface filter. `NetworkPathInterfaceParityTests.testPathMonitorPreStartCancelKeepsInitialCurrentPathMatchingApple` runs that shared contract on Apple Network and the Linux shim. |
| `NWPathMonitor.start(queue:)` | Usable | On Linux, probes currently-up IPv4/IPv6 interfaces once, applies the required interface-type filter, updates `currentPath`, and delivers that snapshot asynchronously. Apple starts a live path subscription; continuous updates, exact Apple path selection, and system DNS policy remain incomplete. |
| `NWPathMonitor.cancel()` after `start(queue:)` / live monitor teardown | Fallback | The shim has no live OS path subscription to tear down, so post-start cancellation is outside the proven pre-start parity contract. Full Apple monitor lifecycle parity depends on a continuous live path subscription. |
| `NWPath` status/unsatisfiedReason/interface/expense/support properties and `usesInterfaceType(_:)` | Parity | The initial monitor path metadata and helper-query results are Apple-checked for the default monitor and every required interface filter. Linux `start(queue:)` snapshots are covered as a usable one-shot contract, but changing interface state and exact live support flags are not at parity. |
| `NWPath.Status` cases / `String(describing:)` / equality / hashing | Parity | Apple-checked status case spellings, string descriptions, same-case equality, cross-case inequality, and equal-value hash coherence; `NetworkPathInterfaceParityTests` runs the same contract on Apple Network and the Linux shim. Linux also exposes `.description` as a compatibility alias, but Apple exposes no direct public `.description` member for this enum, so it is not part of the parity contract. `NWPathMonitor.Status` remains a Linux compatibility alias. |
| `NWPath.UnsatisfiedReason` cases / `String(describing:)` / equality / hashing | Parity | Apple-checked case spellings for `notAvailable`, `cellularDenied`, `wifiDenied`, and `localNetworkDenied`, plus same-case equality, cross-case inequality, and equal-value hash coherence; `NetworkPathInterfaceParityTests` runs the same contract on Apple Network and the Linux shim. Apple exposes no direct `.description` member for this enum, and Linux mirrors that. |
| `NWInterface.InterfaceType` cases / `String(describing:)` / equality / hashing | Parity | Apple-checked interface type case spellings, string descriptions, same-case equality, cross-case inequality, and equal-value hash coherence; `NetworkPathInterfaceParityTests` runs the same contract on Apple Network and the Linux shim. Linux also exposes `.description` as a compatibility alias, but Apple exposes no direct public `.description` member for this enum, so it is not part of the parity contract. |
| `NWInterface` values returned by scoped `IPv4Address`, `IPv6Address`, and `NWEndpoint.Host` parsing | Parity | Apple-checked loopback scope resolution via the local interface index covers `name`, `type`, `String(describing:)`, `debugDescription`, equality, and equal-value hash coherence across named IPv6 scopes, numeric IPv6 scopes, named IPv4 scopes, and scoped DNS host literals. `NetworkPathInterfaceParityTests` resolves the platform loopback name on each OS before running the shared contract. |
| `NWInterface.init(type:)` | Compile-only | Linux compatibility initializer for app source that constructs synthetic interfaces by type. Apple `NWInterface` has no public equivalent initializer, so this constructor is intentionally not marked Parity. |
| Network value protocol surface (`Sendable`, `Hashable`, `CustomDebugStringConvertible`, `RawRepresentable`, `IPAddress`) | Parity | Apple-probed and shared macOS/Linux `NetworkProtocolSurfaceParityTests` pin each value's public protocol constraints and observable string/debug output for `NWEndpoint.Port`, `NWEndpoint.Host`, `NWEndpoint`, `IPv4Address`, `IPv6Address`, `NWPath.Status`, `NWPath.UnsatisfiedReason`, `NWInterface.InterfaceType`, and resolved `NWInterface` values. `IPv6Address.Scope` is pinned to Apple's raw-value and hashable surface without overclaiming `Sendable` or string/debug behavior. Direct `.description` and `CustomStringConvertible` conformance are intentionally excluded for address, host, endpoint, and interface values because Apple does not expose that protocol surface, even where Linux keeps compatibility aliases for app source. |
| `NWProtocolTCP.Options.init()` | Parity | Apple-probed and shared macOS/Linux `NetworkParametersParityTests` pin constructor value text, reference identity, and Sendable surface. This is options-object value-surface parity only; TCP socket behavior remains incomplete. |
| `NWProtocolTCP.Options.noDelay` / `noPush` / `noOptions` / `enableKeepalive` / `retransmitFinDrop` / `disableAckStretching` / `enableFastOpen` / `disableECN` | Parity | Apple-probed defaults are all `false`, and shared macOS/Linux tests pin getter/setter behavior plus unchanged `String(describing:)` and `String(reflecting:)` text after mutation. These properties are stored and reported at parity, but Linux does not yet apply them to real TCP sockets. |
| `NWProtocolTCP.Options.keepaliveCount` / `keepaliveIdle` / `keepaliveInterval` / `maximumSegmentSize` / `connectionTimeout` / `persistTimeout` / `connectionDropTime` | Parity | Apple-probed defaults are all `0`, and shared macOS/Linux tests pin getter/setter behavior plus unchanged value text after mutation. These properties are stored and reported at parity, but Linux does not yet apply them to real TCP sockets. |
| `NWProtocolUDP.Options.init()` / `NWProtocolUDP.Options.preferNoChecksum` | Parity | Apple-probed default for `preferNoChecksum` is `false`, setter behavior stores `true`, and shared macOS/Linux tests pin the constructor/value text. This is UDP option value-surface parity only; datagram checksum/socket behavior remains incomplete. |
| `NWProtocolOptions` / `NWParameters.defaultProtocolStack` / `NWParameters.ProtocolStack.applicationProtocols` / `transportProtocol` / `internetProtocol` | Parity | Apple-probed and shared macOS/Linux `NetworkParametersParityTests` pin the base option type surface, default stack composition for TCP, UDP, TLS, and DTLS parameters, fresh stack wrappers over shared parameter storage, setter copy behavior for application and transport protocol options, and Apple's nil-ignored `internetProtocol` setter behavior. This is protocol-stack value-surface parity only; it does not make connections/listeners or sockets functional. |
| `NWProtocolIP.Options` via `NWParameters.defaultProtocolStack.internetProtocol` / `version` / `hopLimit` / `useMinimumMTU` / `disableFragmentation` / `shouldCalculateReceiveTime` / `localAddressPreference` / `disableMulticastLoopback` | Parity | Apple does not expose a public `NWProtocolIP.Options()` constructor, so the shared tests obtain it through `NWParameters.defaultProtocolStack`. They pin default values, getter/setter persistence through the protocol stack, Sendable/reference surface, and `String(describing:)` / `String(reflecting:)` text. This is IP option value-surface parity only; Linux does not yet apply these settings to packets or sockets. |
| `NWProtocolIP.Options.Version` / `NWProtocolIP.Options.AddressPreference` / `NWProtocolIP.ECN` | Parity | Apple-probed enum case spellings, `String(describing:)`, `String(reflecting:)`, equality, hashability, and Sendable-compatible value surface are covered by shared tests. |
| `NWProtocolTLS.Options.init()` / `NWParameters.tcp` / `.udp` / `.tls` / `.dtls` / `NWParameters.init(tls:tcp:)` / `init(dtls:udp:)` / `NWParameters.Attribution` / `ExpiredDNSBehavior` / `MultipathServiceType` / `ServiceClass` / `requiredInterfaceType` / `prohibitedInterfaceTypes` / `requiredLocalEndpoint` / `allowLocalEndpointReuse` / `includePeerToPeer` / `serviceClass` / `multipathServiceType` / `expiredDNSBehavior` / `allowFastOpen` / `prohibitExpensivePaths` / `prohibitConstrainedPaths` / `requiresDNSSECValidation` / `preferNoProxies` / `attribution` / `NWParameters.debugDescription` / `String(describing:)` / `String(reflecting:)` | Parity | Apple-probed and shared macOS/Linux `NetworkParametersParityTests` pin parameter factory and initializer text for TCP, UDP, TLS, and DTLS, fresh factory identity, policy enum string/reflecting text, policy defaults, getter/setter behavior, empty prohibited-interface normalization, required local endpoint debug formatting including Unix `AF_UNIX:"..."`, and traffic/multipath/fast-open/expense/constrained/cellular/proxy/attribution/DNSSEC debug segments. This is constructor/value/policy-surface parity only; socket creation, TLS policy effects, datagram behavior, and connection/listener semantics remain incomplete. |
| `NWError.posix(_:)` / `.dns(_:)` / `.tls(_:)` / equality / `debugDescription` / `String(describing:)` / `String(reflecting:)` / `localizedDescription` | Parity | Apple-probed and shared macOS/Linux `NetworkErrorParityTests` pin Sendable and Equatable but intentionally not Hashable, Darwin POSIX raw/message output for mapped common errors such as `.ECONNREFUSED`, `DNSServiceErrorType`/`OSStatus` `Int32` payloads, TLS `-9807` invalid-certificate-chain text, DNS unknown text, and Apple localizedDescription formatting. This is value-surface parity only; DNS/TLS transport behavior, connections, listeners, and socket behavior remain incomplete. |
| `IPv4Address.init?(String)` / `init?(Data)` / `String(describing:)` / `debugDescription` | Parity | Apple-checked IPv4 parser covers strict whitespace rejection, legacy 1-4 component forms, decimal/octal/hex components, single-component modulo-32-bit wrapping for oversized decimal and hex values, exact dotted-field bound rejection, empty non-final hex components such as `0x.0.0.1`, four-component decimal-first zero-prefix parsing with octal fallback for over-range octal-compatible fields, 4-byte data validation, scoped interface literals through resolved OS interface names, canonical dotted-decimal string/debug output, and equality/hash coherence across parsed, data-backed, and scoped name-backed values. `NetworkIPAddressParityTests` adds Apple-observed 3/4/5-byte data initializer boundaries, classifier-edge string/debug checks, direct address equality/hash checks, and a seeded IPv4 parser corpus for these legacy initializer edge cases. Linux also exposes `.description` as a compatibility alias, but direct `.description` is not an Apple public API for this value. |
| `IPv4Address.any` / `.broadcast` / `.loopback` / `.allHostsGroup` / `.allRoutersGroup` / `.allReportsGroup` / `.mdnsGroup` | Parity | Apple-checked raw values and string/debug output for the public IPv4 address constants. |
| `IPv4Address.interface` / `isLoopback` / `isLinkLocal` / `isMulticast` | Parity | Apple-checked nil interface for unscoped literal/data construction, scoped literal interface preservation through resolved OS interface names, scoped name-backed equality/hash behavior, plus exact loopback, `169.254/16` link-local, and `224/4` multicast classification for tested edge cases. The dedicated parity matrix includes Apple boundary behavior such as only `127.0.0.1` reporting loopback, `169.254.0.0` through `169.254.255.255` reporting link-local, and `224.0.0.0` through `239.255.255.255` reporting multicast. |
| `IPv6Address.init?(String)` / `init?(Data)` / `String(describing:)` / `debugDescription` | Parity | Apple-checked IPv6 parser covers `inet_pton` literal acceptance, whitespace rejection, 16-byte data validation, scoped interface literals through resolved OS interface names, empty and unresolved scope suffix fallback to unscoped IPv6 values, malformed double-scope rejection, canonical `inet_ntop` string/debug output, and equality/hash coherence across parsed, data-backed, and scoped name-vs-numeric-interface values. `NetworkIPAddressParityTests` adds Apple-observed 15/16/17-byte data initializer boundaries, string/debug checks for classifier edges, invalid scoped non-IPv6 rejection, and direct address equality/hash checks. Linux also exposes `.description` as a compatibility alias, but direct `.description` is not an Apple public API for this value. |
| `IPv6Address.any` / `.broadcast` / `.loopback` / `.nodeLocalNodes` / `.linkLocalNodes` / `.linkLocalRouters` | Parity | Apple-checked raw values and string/debug output for the public IPv6 address constants. Apple reports `.broadcast` as the all-zero `::` value. |
| `IPv6Address.Scope` / `interface` / `isAny` / `isLoopback` / `isIPv4Compatabile` / `isIPv4Mapped` / `asIPv4` / `is6to4` / `isLinkLocal` / `isMulticast` / `multicastScope` / `isUniqueLocal` | Parity | Apple-checked nil interface for unscoped literal/data construction, scoped literal interface preservation through resolved OS interface names, scoped name-vs-numeric interface equality/hash behavior, the Apple spelling `isIPv4Compatabile`, IPv4-compatible/mapped extraction behavior, `2002::/16` 6to4 detection, `fe80::/10` link-local detection, `fc00::/7` unique-local detection, multicast scope raw values for the tested edge cases, `IPv6Address.Scope` failable raw construction for known/unknown raw values, and scope equality/hash coherence. Apple Network does not expose an `IPv6Address.isSiteLocal` address classifier, and the Linux shim keeps that Linux-only surface absent while still supporting `.siteLocal` multicast scope. |
| `NWEndpoint.Host.init(_:)` / direct host cases / `description` / `debugDescription` / equality / hashing | Parity | Shared macOS/Linux `NetworkEndpointHostParityTests` cover Apple-matching scoped and unscoped IPv4 literals, IPv6 literals, DNS names, empty-string normalization to `.`, IPv4-mapped IPv6 host literals such as `::ffff:192.0.2.1`, direct `.name`, `.ipv4`, and `.ipv6` case descriptions, debug text, parsed-to-direct case equality, scoped name-vs-numeric-scope equality, scoped-vs-unscoped inequality, and equal-value hash coherence. |
| `NWEndpoint.Host` scoped interface literals | Parity | Shared macOS/Linux tests cover IPv6 link-local scopes, numeric scope normalization through `if_indextoname`, scoped IPv4 literals, IPv4-mapped scoped IPv6 normalization, scoped DNS names, empty or unresolved IPv6 scope fallback to an unscoped address, empty or unresolved IPv4-mapped scope fallback to an unscoped IPv4 host, malformed double-scope and scoped DNS/IPv4 fallback to `.name`, scoped parsed-to-direct equality, and scoped equal-value hash coherence. Platform interface names differ, so the contract resolves the local loopback interface by index on each OS. |
| `NWEndpoint.Port.init?(String)` / `init?(rawValue:)` / integer literal / `rawValue` / equality / hashing / `String(describing:)` / `debugDescription` | Parity | Apple-checked port parsing covers leading C whitespace, plus signs, negative zero variants, decimal-only input, UInt16 bounds, trailing-character rejection, non-ASCII whitespace rejection, failable raw-value construction, integer literals, decimal debug/string-describing output, and equality/hash coherence across parsed, raw, literal, and known-constant values. The shared macOS/Linux `NetworkEndpointPortParityTests` contract now includes a deterministic seeded fuzz corpus and runs against Apple `Network` on macOS and the shim on Linux. Direct `.description` is not an Apple public API for this value and is intentionally not cloned. |
| `NWEndpoint.Port.any` / `.ssh` / `.smtp` / `.http` / `.pop` / `.imap` / `.https` / `.imaps` / `.socks` | Parity | Apple-checked well-known port constants expose raw values `0`, `22`, `25`, `80`, `110`, `143`, `443`, `993`, and `1080`, with matching debug/string-describing output. The shared macOS/Linux `NetworkEndpointPortParityTests` contract keeps this narrow public value surface at Parity while the broader Network stack remains incomplete. |
| `NWEndpoint.hostPort`, `service`, and `unix` value `description` / `debugDescription` / equality / hashing | Parity | Shared macOS/Linux `NetworkEndpointHostParityTests` cover Apple-checked host-port, Unix path, and DNS-SD service string/debug descriptions, including IPv6 host-port separator behavior, IPv4-mapped host-port normalization, service type/domain trailing-dot normalization, service-name escaping for dots, spaces, and backslashes, empty-name/domain cases, valid `_tcp`/`_udp` service type formatting, invalid-type raw concatenation, leading/internal domain dot preservation, scoped service `@interface` suffixes for valid DNS-SD names with a non-empty domain, scoped `%interface` suffixes for invalid or domainless service forms, and associated service interface value preservation. The same shared contract verifies exact value equality, scoped host-port and scoped service equality, cross-case and changed-associated-value inequality, scoped-vs-unscoped host-port and service inequality, and equal-value hash coherence for host-port, service, and Unix endpoints. |
| Connections, listeners, continuous path subscriptions, DNS/TLS transport behavior, UDP/TCP socket behavior, IP packet/socket option effects | Incomplete | Required for Network Parity. |

## NetworkExtension

| API or function | Linux status | Notes |
| --- | --- | --- |
| `NEPacketTunnelProvider.setTunnelNetworkSettings(_:completionHandler:)` | Fallback | Calls completion with nil; no tunnel configuration. |
| `NEPacketTunnelNetworkSettings.init(tunnelRemoteAddress:)` | Compile-only | Property bag. |
| `NEIPv4Settings.init(addresses:subnetMasks:)` / route properties | Compile-only | Property bag. |
| `NEIPv4Route.default()` | Compile-only | Default route shape only. |
| `NEIPv6Settings.init(addresses:networkPrefixLengths:)` / route properties | Compile-only | Property bag. |
| `NEIPv6Route.default()` | Compile-only | Default route shape only. |
| `NEDNSSettings.init(servers:)` | Compile-only | Property bag. |
| Packet flow, VPN lifecycle, tunnel routing, provider extension hosting | Incomplete | Required for NetworkExtension Parity. |

## CoreGraphics

| API or function | Linux status | Notes |
| --- | --- | --- |
| `CGEventSource.init?(stateID:)` | Compile-only | Source object shape only. |
| `CGEventSource.keyState(_:key:)` | Fallback | Records diagnostic and returns false. |
| `CGEvent.init?(keyboardEventSource:virtualKey:keyDown:)` | Compile-only | Event object shape only. |
| `CGEvent.post(tap:)` | Fallback | Records diagnostic, no synthetic input. |
| `CGEvent.keyboardSetUnicodeString(stringLength:unicodeString:)` | Compile-only | No-op. |
| Real event taps, keyboard state, pointer events, drawing APIs beyond imported Foundation/CoreFoundation geometry | Incomplete | Required for CoreGraphics Parity. |

## Security

| API or function | Linux status | Notes |
| --- | --- | --- |
| `SecCertificateCreateWithData(_:_:)` | Partial | Wraps DER data in a certificate container. |
| `SecTrustSetAnchorCertificates(_:_:)` | Fallback | Returns `errSecSuccess`, stores no trust chain. |
| `SecTrustSetAnchorCertificatesOnly(_:_:)` | Fallback | Returns `errSecSuccess`, stores no trust chain. |
| `SecTrustEvaluateWithError(_:_:)` | Fallback | Records diagnostic and returns true. |
| Keychain, certificate parsing, policy evaluation, platform trust store, Secure Transport parity | Incomplete | Current fallback must not be treated as production TLS trust. |

## AVFoundation

| API or function | Linux status | Notes |
| --- | --- | --- |
| `AVSpeechSynthesizer.speak(_:)` | Fallback | Records diagnostic and calls start/finish delegate callbacks immediately. |
| `AVSpeechSynthesizer.stopSpeaking(at:)` | Fallback | Returns true without native speech output. |
| `AVSpeechSynthesizer.continueSpeaking()` / `pauseSpeaking(at:)` | Compile-only | Return false. |
| `AVSpeechUtterance.init(string:)` | Compile-only | Stores utterance metadata. |
| `AVSpeechSynthesisVoice` initializers and voice metadata | Compile-only | Static metadata only. |
| `AVAudioSession.sharedInstance()`, `setCategory`, `setActive` | Fallback | No native audio-session effect. |
| `AVPlayer.init(url:)` | Compile-only | Stores URL/player shape only. |
| `AVAudioEngine.prepare()` / `start()` / `stop()` / `reset()` | Fallback | Records diagnostics and toggles `isRunning`; no audio I/O. |
| `AVAudioEngine.attach(_:)` / `connect(...)` | Compile-only | No real graph processing. |
| `AVAudioNode.installTap(...)` / `removeTap(onBus:)` | Fallback | Records diagnostic, no audio tap stream. |
| `AVAudioFormat`, `AVAudioPCMBuffer`, `AVAudioTime` initializers | Compile-only | Data containers only. |
| Real synthesis, playback, capture, engine graph processing, media decoding | Incomplete | Required for AVFoundation Parity. |

## AVKit

| API or function | Linux status | Notes |
| --- | --- | --- |
| `VideoPlayer.init(player:)` | Compile-only | Source-compatible SwiftUI view. |
| `VideoPlayer.body` | Compile-only | Empty view; no video rendering. |

## Speech

| API or function | Linux status | Notes |
| --- | --- | --- |
| `SFSpeechRecognizer.init(locale:)` | Fallback | Creates unavailable recognizer shape. |
| `SFSpeechRecognizer.authorizationStatus()` | Fallback | Returns `.denied`. |
| `SFSpeechRecognizer.requestAuthorization(_:)` | Fallback | Records diagnostic and returns `.denied`. |
| `SFSpeechRecognizer.recognitionTask(with:resultHandler:)` | Fallback | Records diagnostic and returns task object only. |
| `SFSpeechAudioBufferRecognitionRequest.append(_:)` | Compile-only | No-op. |
| `SFSpeechRecognitionTask.cancel()` | Compile-only | No-op. |
| Real speech recognition, audio transcription, authorization bridge | Incomplete | Required for Speech Parity. |

## PhotosUI and Photos

| API or function | Linux status | Notes |
| --- | --- | --- |
| `PhotosPickerItem.init()` | Compile-only | Item shape only. |
| `PhotosPicker.init(selection:label:)` | Compile-only | Returns label body; no picker. |
| `Photos` product import | Compile-only | Re-exports shared shims only. |
| Photo-library authorization, asset fetching, picker UI, transferable item loading | Incomplete | Required for Photos parity. |

## Charts

| API or function | Linux status | Notes |
| --- | --- | --- |
| `Chart.init(content:)` | Compile-only | Source-compatible view wrapper. |
| `BarMark`, `LineMark`, `PointMark`, `AreaMark`, `RuleMark`, `SectorMark` initializers | Compile-only | Empty mark views. |
| `PlottableValue.value(_:_:)` and global `value(_:_:)` helpers | Compile-only | Metadata spelling only. |
| Axes, scales, legends, rendering, interaction, accessibility | Incomplete | Required for Charts Parity. |

## StoreKit

| API or function | Linux status | Notes |
| --- | --- | --- |
| `Product` type | Compile-only | Placeholder type only. |
| Product lookup, purchases, transactions, verification, subscriptions | Incomplete | Required for StoreKit Parity. |

## TipKit

| API or function | Linux status | Notes |
| --- | --- | --- |
| `Tip` protocol | Compile-only | Protocol spelling only. |
| `TipView.init(_:)` | Compile-only | Source-compatible view wrapper. |
| `TipView.body` | Compile-only | Empty view. |
| Tip rules, persistence, display frequency, popovers | Incomplete | Required for TipKit Parity. |

## Observation

| API or function | Linux status | Notes |
| --- | --- | --- |
| `@Observable` | Partial | Lowers through `QuillObservableMacro`; enough for current source transforms. |
| Observation tracking, invalidation, access lists, registrar parity | Incomplete | Required for Observation Parity. |

## ApplicationServices

| API or function | Linux status | Notes |
| --- | --- | --- |
| `AXIsProcessTrustedWithOptions(_:)` | Partial | Returns `QuillAccessibility.isTrusted`. |
| `AXUIElementCreateSystemWide()` | Compile-only | Creates system-wide element shape. |
| `AXUIElementCopyAttributeValue(...)` | Compile-only | Returns failure. |
| Accessibility tree inspection, mutation, notifications, app targeting | Incomplete | Required for ApplicationServices Parity. |

## ServiceManagement

| API or function | Linux status | Notes |
| --- | --- | --- |
| `SMAppService.mainApp` | Partial | Backed by current `QuillLaunchService`. |
| `SMAppService.status` | Partial | Mirrors current launch-service state. |
| `SMAppService.register()` / `unregister()` | Usable | Registers/unregisters through the current Quill launch-service abstraction. |
| Full login item parity, privileged helpers, platform service managers | Incomplete | Required for ServiceManagement Parity. |

## AsyncAlgorithms

| API or function | Linux status | Notes |
| --- | --- | --- |
| `AsyncTimerSequence.init(interval:clock:)` | Usable | Stores interval and clock. |
| `AsyncTimerSequence.Iterator.next()` | Usable | Sleeps for the interval and yields `clock.now`, stops on cancellation. |
| Other AsyncAlgorithms package algorithms | Incomplete | Only timer sequence subset exists here. |

## Carbon

| API or function | Linux status | Notes |
| --- | --- | --- |
| `CarbonEventHotKeyID` | Compile-only | Struct spelling only. |
| `CarbonCompatibility.available` | Compile-only | Always false. |
| Hot-key registration, event targets, classic Carbon APIs | Incomplete | Required for any Carbon behavior parity. |

## Combine

| API or function | Linux status | Notes |
| --- | --- | --- |
| OpenCombine re-export | Partial | Broad Combine surface comes from OpenCombine, not local Apple SDK code. |
| `AnyPublisher.init()` where `Failure == Never` | Usable | Creates an empty publisher. |
| `Publishers.Merge` local implementation | Partial | Current merge behavior exists, but full Apple Combine edge-case parity is incomplete. |
| Backpressure, scheduler, demand, cancellation, and operator fuzz parity | Incomplete | Required before claiming Combine Parity. |

## os

| API or function | Linux status | Notes |
| --- | --- | --- |
| `Logger.init(...)` | Usable | Stores subsystem/category. |
| `Logger.debug/info/notice/warning/error/fault/critical/trace` overloads | Partial | Records diagnostics and prints; not Apple unified logging. |
| `os_log(...)` | Partial | Diagnostic print path only. |
| `_dyld_image_count()` / `_dyld_get_image_name(_:)` | Compile-only | Return zero/nil. |
| `OSAllocatedUnfairLock.withLock(_:)` | Partial | Provides local locking semantics, not kernel unfair-lock parity. |
| `OSSignposter` methods | Compile-only | No real signpost tracing. |
| Unified logging persistence, signpost tooling, dyld image inspection parity | Incomplete | Required for os Parity. |

## IOKit

| API or function | Linux status | Notes |
| --- | --- | --- |
| `IONotificationPortCreate(_:)` | Compile-only | Returns null. |
| `IONotificationPortDestroy(_:)` / `IONotificationPortSetDispatchQueue(_:_:)` | Compile-only | No-op. |
| `IOServiceMatching(_:)` | Compile-only | Returns null. |
| `IOServiceAddMatchingNotification(...)` | Fallback | Returns unsupported. |
| `IOIteratorNext(_:)` | Fallback | Returns zero. |
| `IOObjectRelease(_:)` | Fallback | Returns success. |
| USB/device discovery, notifications, registry traversal | Incomplete | Required for IOKit Parity. |

## Re-export-only Apple shims

These packages currently exist so imports compile and shared Quill types are in
scope. They do not implement standalone Apple framework behavior yet.

| Package | Linux status | Notes |
| --- | --- | --- |
| `MessageUI` | Compile-only | Re-exports `QuillFoundation` and `QuillUIKit`; mail composer behavior is incomplete. |
| `SafariServices` | Compile-only | Re-exports `QuillFoundation` and `QuillUIKit`; Safari view services are incomplete. |
| `MobileCoreServices` | Compile-only | Re-exports `QuillFoundation`; legacy UTI constants beyond shared fallbacks are incomplete. |
| `LocalAuthentication` | Compile-only | Re-exports `QuillShims`; biometric/passcode auth is incomplete. |
| `CoreSpotlight` | Compile-only | Re-exports `QuillShims`; indexing/search APIs are incomplete. |

## Third-Party and App-Support Package Clones

These packages are not Apple frameworks, but current app ports import them as if
their upstream packages were present. They are listed function by function so
app progress can be audited with the same status ladder.

### Package Clone Summary

| Package area | Complete function rows today | Incomplete function rows and parity blockers |
| --- | --- | --- |
| `Alamofire` | URL string request creation for GET/POST, URLSession-backed transport, status-code validation, and JSON `Decodable` response callbacks. | Upload/download, interceptors, authentication, retry policies, request/response serializers beyond JSON decoding, trust evaluation parity, cancellation/progress, and fuzz parity against upstream Alamofire. |
| `OllamaKit` | Base URL setup, model listing, reachability probing, current chat streaming contracts, response decoding, and app-facing Codable models. | Full upstream API breadth, retries, tool-call/event streaming details, transport customization edge cases, and Apple/Linux fuzz parity beyond current Enchanted flows. |
| `KeychainSwift` | Prefix-scoped in-memory string, data, bool, delete, and clear flows. | Secure OS keychain persistence, access control, synchronization, accessibility classes, and cross-process behavior. |
| Markdown/code packages | `MarkdownUI` parsing/rendering subset, plain-text extraction, highlighter injection, `Splash` theme/token highlighting subset. | Full CommonMark/GitHub Markdown, exact MarkdownUI styling/layout, complete Swift tokenization, HTML output parity, and typography/rendering fidelity. |
| UI helper packages | `ActivityIndicatorView`, `WrappingHStack`, `Vortex`, `KeyboardShortcuts`, `Magnet`, and `Sparkle` expose app-facing shapes. | Animations, true wrapping layout, particle effects, native shortcut recording/global hotkeys, updater behavior, and platform services. |
| App support shims | `Tidemark`, `Secrets`, `QuillRS`, `SwiftUIIntrospect`, `SwiftUIDesignSystem`, `Zip`, and `RSDatabase` compile current app source. | CommonMark conversion, secret storage, browser integration, tree/path parity, introspection callbacks, real zip/database APIs, and broader upstream semantics. |

### Alamofire

| API or function | Linux status | Notes |
| --- | --- | --- |
| `ServerTrustEvaluating.evaluate(_:forHost:)` | Compile-only | Protocol spelling exists for app source compatibility. |
| `ServerTrustManager.init(evaluators:)` | Compile-only | Stores evaluator shape for app source compatibility; Linux trust policy is not evaluated yet. |
| `HTTPMethod.get` / `.post` | Usable | Maps to `GET` and `POST` request methods. |
| `Session.request(_:method:)` | Usable | Builds URL requests and runs them through URLSession-backed transport. |
| `DataRequest.validate(statusCode:)` | Usable | Records acceptable HTTP status ranges and rejects out-of-range responses. |
| `DataRequest.responseDecodable(...)` | Usable | Delivers JSON `Decodable` success/failure results on the requested dispatch queue. |
| Upload/download, interceptors, authentication, retries, serializers beyond JSON, progress, cancellation, trust evaluation parity | Incomplete | Required before claiming Alamofire parity. |

### OllamaKit

| API or function | Linux status | Notes |
| --- | --- | --- |
| `OllamaKit.init(baseURL:bearerToken:transport:)` | Usable | Builds configured clients for Enchanted model/chat flows. |
| `URLSessionOllamaKitTransport.data(for:)` | Usable | Uses `URLSession` for real HTTP transport. |
| `models()` | Usable | Requests `/api/tags`, validates HTTP status, and decodes `OKModelsResponse`. |
| `reachable()` | Usable | Probes `models()` and returns a boolean. |
| `chat(data:) -> AnyPublisher<OKChatResponse, Error>` | Usable for current app contract | Runs the chat request and publishes decoded responses; full Combine demand/backpressure parity remains outside this row. |
| `chat(data:) -> AsyncThrowingStream<OKChatResponse, Error>` | Usable | Streams decoded chat responses through an async sequence. |
| `decodeChatResponses(from:)` | Usable | Decodes either newline-delimited JSON responses or a single JSON response. |
| `OKModelsResponse`, `OKModelResponse`, `OKModelDetails` | Usable | Codable model-list payloads used by Enchanted. |
| `OKCompletionOptions`, `OKChatRequestData`, `OKChatResponse` | Usable | Codable request/response shapes for current chat flows, including text and optional image payloads. |
| Embeddings, generation-only APIs, tool calls, detailed streaming events, retry policy, cancellation fuzz parity | Incomplete | Required for upstream OllamaKit parity. |

### KeychainSwift

| API or function | Linux status | Notes |
| --- | --- | --- |
| `KeychainSwift.init()` / `init(keyPrefix:)` | Usable | Creates a process-local in-memory store with optional key prefixing. |
| `set(_:forKey:)` for `String`, `Data`, and `Bool` | Usable | Stores values in memory and returns success. |
| `get(_:)`, `getData(_:)`, `getBool(_:)` | Usable | Round trips values written through the current shim. |
| `delete(_:)` | Usable | Removes one prefix-scoped key and returns success. |
| `clear()` | Usable | Removes all values for the prefix. |
| Keychain access groups, secure persistence, access-control flags, synchronization, cross-process lookup | Incomplete | Required before claiming KeychainSwift parity. |

### MarkdownUI

| API or function | Linux status | Notes |
| --- | --- | --- |
| `Markdown.init(_:)` | Partial | Stores source and renders the local parsed block tree. |
| `Markdown.body` | Partial | Renders paragraphs, headings, lists, quotes, code blocks, tables, and image placeholders through SwiftUI views. |
| `Markdown.plainText(from:)` | Usable | Deterministically extracts plain text from the parsed subset. |
| `CodeSyntaxHighlighter.highlightCode(_:language:)` | Usable | Protocol and plain-text highlighter support current code-block rendering. |
| `markdownCodeSyntaxHighlighter(_:)` | Usable | Stores the highlighter for `Markdown` rendering; view-level overload is a pass-through. |
| `markdownTheme(_:)`, `Theme` builder methods | Fallback | Builder closures compile and receive sample configurations, but styling is not applied with MarkdownUI fidelity. |
| `MarkdownLength`, `markdownMargin`, `relativeLineSpacing`, `relativePadding`, `relativeFrame` | Partial | Converts relative lengths into current SwiftUI padding/spacing/frame metadata where possible. |
| Full CommonMark/GitHub Markdown, inline/link/image behavior, table layout, styling cascade, accessibility, upstream renderer parity | Incomplete | Required before claiming MarkdownUI parity. |

### Splash

| API or function | Linux status | Notes |
| --- | --- | --- |
| `SplashColor`, `Color.init(_:)`, `Font` | Usable | App-facing color/font value shapes compile and round trip. |
| `TokenType` | Usable | Exposes the token categories used by current highlighting tests. |
| `Theme.sunset(withFont:)` / `wwdc17(withFont:)` | Usable | Builds deterministic theme payloads. |
| `OutputBuilder` / `OutputFormat` | Usable | Generic builder protocol surface supports current custom output formats. |
| `SyntaxHighlighter.highlight(_:)` | Usable | Tokenizes deterministically on whitespace and classifies comments, strings, numbers, keywords, uppercase types, and plain text. |
| Full Swift lexer, grammar-aware highlighting, HTML/attributed output parity, upstream theme fidelity | Incomplete | Required before claiming Splash parity. |

### ActivityIndicatorView

| API or function | Linux status | Notes |
| --- | --- | --- |
| `ActivityIndicatorView.init(isVisible:type:)` | Usable | Stores visibility binding and style. |
| `ActivityIndicatorView.IndicatorType.rotatingDots(count:)` / `.growingCircle` | Usable | Covers the styles current app source imports. |
| `ActivityIndicatorView.body` | Partial | Renders static dots or a circle when visible. |
| Animation timing, drawing fidelity, all upstream indicator styles | Incomplete | Required for ActivityIndicatorView parity. |

### WrappingHStack

| API or function | Linux status | Notes |
| --- | --- | --- |
| `WrappingHStack.init(...)` | Usable | Captures alignment, spacing, and content for current source compatibility. |
| `WrappingHStack.body` | Partial | Renders a plain `HStack`; it does not measure and wrap children. |
| Dynamic wrapping, line spacing, measurement, accessibility order, upstream layout parity | Incomplete | Required for WrappingHStack parity. |

### Vortex

| API or function | Linux status | Notes |
| --- | --- | --- |
| `VortexSystem.splash` | Compile-only | Provides the named system used by app source. |
| `VortexSystem.makeUniqueCopy()` | Fallback | Returns `self`; no unique particle state is allocated. |
| `VortexView.init(_:content:)` | Usable | Captures the requested system and content. |
| `VortexView.body` | Partial | Renders content in a `ZStack` without particle effects. |
| Particle simulation, emitters, timing, animation, rendering fidelity | Incomplete | Required for Vortex parity. |

### KeyboardShortcuts

| API or function | Linux status | Notes |
| --- | --- | --- |
| `KeyboardShortcuts.Shortcut`, `Key`, `Name` | Usable | Codable/hashable shortcut identity and default values work for current app settings. |
| `getShortcut(for:)` / `setShortcut(_:for:)` | Usable | Stores shortcuts in `UserDefaults` with locking. |
| `reset(_:)` / `resetAll()` | Usable | Restores defaults or clears stored shortcut values. |
| `KeyboardShortcuts.Recorder.body` | Partial | Renders a text label for current settings screens. |
| `View.onKeyboardShortcut(...)` | Compile-only | Returns `self`; actions are not registered. |
| Native recorder UI, global shortcut registration, event delivery, conflict handling | Incomplete | Required for KeyboardShortcuts parity. |

### Magnet

| API or function | Linux status | Notes |
| --- | --- | --- |
| `Key.space`, `Key.escape`, `.character(_:)` | Compile-only | Covers current hot-key declarations. |
| `_Modifiers` / `KeyCombo.init?` | Compile-only | Stores key/modifier payloads. |
| `HotKey.init(...)` | Partial | Stores identifier, combo, and handler. |
| `HotKey.register()` / `unregister()` | Compile-only | No-op; no native hot key is installed. |
| `HotKey.trigger()` | Usable | Test helper invokes the stored handler. |
| Global Carbon/AppKit hot-key registration, event routing, conflict detection | Incomplete | Required for Magnet parity. |

### Sparkle

| API or function | Linux status | Notes |
| --- | --- | --- |
| `SPUUpdater.canCheckForUpdates` | Fallback | Always false. |
| `SPUUpdater.checkForUpdates()` | Compile-only | No-op. |
| `SPUStandardUpdaterController.updater` | Compile-only | Exposes an updater object for source compatibility. |
| Appcast fetching, signature checks, update UI, installer/relaunch behavior | Incomplete | Required for Sparkle parity. |

### Tidemark

| API or function | Linux status | Notes |
| --- | --- | --- |
| `markdownToHTML(_:)` | Fallback | Escapes `&`, `<`, and `>`, trims whitespace, returns empty output for empty input, and wraps non-empty text in one paragraph. |
| CommonMark parsing, links/images/lists/tables/code, HTML fidelity | Incomplete | Required for Tidemark parity. |

### Secrets

| API or function | Linux status | Notes |
| --- | --- | --- |
| `SecretKey` constants | Compile-only | Constants exist but currently return empty strings. |
| `CredentialsType` | Usable | Defines the credential categories current app source imports. |
| `Credentials.init(type:username:secret:)` | Usable | Stores credential payloads. |
| `CredentialsManager.storeCredentials(...)` / `removeCredentials(...)` | Fallback | No-op. |
| `CredentialsManager.retrieveCredentials(...)` | Fallback | Always returns nil. |
| Secure secret loading, keychain persistence, OAuth/session storage | Incomplete | Required for Secrets parity. |

### QuillRS

| API or function | Linux status | Notes |
| --- | --- | --- |
| `TreeController.init(delegate:)` / `rebuild()` | Partial | Builds a root node and refreshes delegate-provided root children. |
| `Node.init(...)`, `existingOrNewChildNode`, `childNodeRepresentingObject`, `createChildNode` | Usable | Provides in-memory tree nodes for NetNewsWire-style source compatibility. |
| `NodePath.init(...)` | Compile-only | Initializers currently return nil. |
| `postUnreadCountDidChangeNotification()` | Compile-only | No-op. |
| `Browser.open(_:inBackground:)` | Compile-only | No-op. |
| `NSString.rs_SQLValueList(withPlaceholders:)` | Usable | Returns deterministic SQL placeholder lists or nil for zero. |
| `NSObject.preferredLink`, `attributionString`, `linkString` | Fallback | Return nil or empty strings. |
| `IconImage.init(image:isDark:)` / `NonIntrinsicImageView` | Compile-only | App-facing image wrapper and image-view subclass shapes exist. |
| Browser integration, notification routing, full tree/path behavior, pasteboard ownership | Incomplete | Required for QuillRS parity. |

### SwiftUIIntrospect and SwiftUIDesignSystem

| API or function | Linux status | Notes |
| --- | --- | --- |
| `View.introspect(_:on:perform:)` | Fallback | Returns `self`; the action is not called. |
| `View.designSystem()` | Fallback | Returns `self`; no design-system environment is applied. |
| Native view lookup, platform-specific introspection callbacks, design-system styling | Incomplete | Required for parity with those packages. |

### QuillSwiftUICompatibility and UIKitLinux

| API or function | Linux status | Notes |
| --- | --- | --- |
| SwiftOpenUI re-export | Usable | Provides the Linux SwiftUI-shaped base module. |
| `Font.Weight = FontWeight` | Usable | Alias preserves source compatibility. |
| `VerticalAlignment.firstTextBaseline` / `.lastTextBaseline` | Fallback | Map to `.top` and `.bottom`. |
| `CGFloat = Double` | Usable | Keeps UIKit-shaped geometry source compiling. |
| `UIScreen.main.bounds` | Fallback | Returns a fixed 1000x800 rectangle. |
| `UIResponder`, `UIView`, `UIViewController.view`, `UISplitViewController.DisplayMode` | Compile-only | Type shapes exist for current Linux source compatibility. |
| Real SwiftUI baseline metrics, UIKit device/screen state, responders, view hierarchy, controllers | Incomplete | Required for parity. |

### Re-Export-Only App Package Shims

| Package | Linux status | Notes |
| --- | --- | --- |
| `Zip` | Compile-only | Re-exports `QuillRS`; zip archive behavior is not implemented here. |
| `RSDatabase` | Compile-only | Re-exports `QuillShims`; database package behavior is not implemented here. |

## App Progress Summary

Function coverage only matters if app targets can use it. Current app-level
progress is tracked in more detail in `docs/app-targets.md`.

| App target | Current level | Main blockers to Parity |
| --- | --- | --- |
| Enchanted GTK | Usable target in progress | Remaining SwiftUI/AppKit behavior gaps, visual parity checks against macOS, and performance baselines. |
| Enchanted Qt | Usable target in progress | Same macOS parity target as GTK, plus independent Qt backend rendering and interaction validation. |
| Quill Chat / legacy aliases | Partial | Naming compatibility is secondary to Enchanted, but aliases must keep building. |
| Smoke/demo targets | Usable for contract checks | Need broader generated source-contract and fuzz coverage across every Apple shim. |
