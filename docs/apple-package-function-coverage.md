# Apple Package Function Coverage

This ledger tracks the Apple-framework compatibility packages exposed by
QuillUI on Linux. It is source-inspected from the current repository, not yet a
generated ABI diff against Apple SDKs. APIs not listed here should be treated as
incomplete on Linux until a source-contract test or implementation row is added.

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
| `NSWorkspace.selectFile`, `activateFileViewerSelecting`, icon/application lookup | Compile-only | No real desktop integration on Linux. |
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
| `UTType.init?(filenameExtension:)` | Partial | Maps a fixed known extension set. |
| `UTType.conforms(to:)` | Partial | Uses a small local parent graph. |
| Static UTTypes such as `.item`, `.content`, `.data`, `.text`, `.plainText`, `.json`, `.image`, `.png`, `.jpeg`, `.movie`, `.audio`, `.pdf` | Partial | Current common identifiers exist. |
| System registry lookup, dynamic/exported/imported types, full conformance graph | Incomplete | Required for UTType Parity. |

## Network

| API or function | Linux status | Notes |
| --- | --- | --- |
| `NWPathMonitor.init()` / `init(requiredInterfaceType:)` | Compile-only | Object shape and stored path only. |
| `NWPathMonitor.start(queue:)` | Fallback | Asynchronously reports current default path once. |
| `NWPathMonitor.cancel()` | Compile-only | No-op. |
| `NWPath` status/interface/expense properties | Compile-only | Static/default metadata only. |
| `NWInterface.init(type:)` | Compile-only | Stores type only. |
| `IPv4Address.init?(String)` / `init?(Data)` | Partial | Dotted IPv4 and 4-byte data parsing. |
| `IPv6Address.init?(String)` / `init?(Data)` | Incomplete | Data length works; string parsing is placeholder-level. |
| `NWEndpoint.Host.init(_:)` | Partial | IPv4/name shape exists; IPv6/name classification needs stricter parsing. |
| `NWEndpoint.Port.init?(String)` / `init(rawValue:)` / integer literal | Partial | Numeric port parsing only. |
| Connections, listeners, real path probing, DNS, TLS, UDP/TCP behavior | Incomplete | Required for Network Parity. |

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

## App Progress Summary

Function coverage only matters if app targets can use it. Current app-level
progress is tracked in more detail in `docs/app-targets.md`.

| App target | Current level | Main blockers to Parity |
| --- | --- | --- |
| Enchanted GTK | Usable target in progress | Remaining SwiftUI/AppKit behavior gaps, visual parity checks against macOS, and performance baselines. |
| Enchanted Qt | Usable target in progress | Same macOS parity target as GTK, plus independent Qt backend rendering and interaction validation. |
| Quill Chat / legacy aliases | Partial | Naming compatibility is secondary to Enchanted, but aliases must keep building. |
| Smoke/demo targets | Usable for contract checks | Need broader generated source-contract and fuzz coverage across every Apple shim. |
