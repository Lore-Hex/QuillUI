#if canImport(Foundation)
import Foundation
#endif

// MARK: - Commands protocol

/// A type that represents a set of app-level menu commands.
///
/// Commands provide menu bar integration on desktop platforms.
/// The `body` property declares command groups and items.
///
/// ```swift
/// struct FileCommands: Commands {
///     @FocusedValue(\.document) var document
///     var body: some Commands {
///         CommandGroup(replacing: .newItem) {
///             CommandMenuItem("Save", shortcut: .init("s")) {
///                 document?.save()
///             }
///             .disabled(document == nil)
///         }
///     }
/// }
/// ```
///
/// `CommandMenuItem` is the backend representation used after command content
/// has been extracted. App code may use Apple's `CommandMenu { Button(...) }`
/// spelling; `CommandMenuBuilder` lifts those small view trees into command
/// items while preserving labels, disabled state, shortcuts, and actions.
/// `@MainActor @preconcurrency` like Apple's SwiftUI.Commands: command
/// closures (Button actions in CommandMenu content) are formed inside the
/// isolated `body`, so they inherit main-actor isolation and can call into
/// app state, exactly as on macOS.
@MainActor @preconcurrency
public protocol Commands {
	associatedtype Body: Commands
	@CommandsBuilder var body: Body { get }
}

// MARK: - EmptyCommands

/// A commands type that contains no commands.
public struct EmptyCommands: Commands {
	public typealias Body = Never
	public var body: Never { fatalError() }
	public init() {}
}

extension Never: Commands {}

// MARK: - CommandGroupPlacement

/// Where a command group should appear in the menu bar.
public enum CommandGroupPlacement: Equatable, Hashable {
	/// A custom top-level command menu by title.
	case menu(String)
	/// Replaces the New Item commands (File menu).
	case newItem
	/// Replaces the app settings command.
	case appSettings
	/// Replaces the Save commands (File menu).
	case saveItem
	/// Replaces the Print commands (File menu).
	case printItem
	/// Replaces the Undo/Redo commands (Edit menu).
	case undoRedo
	/// Replaces the Pasteboard commands (Edit menu).
	case pasteboard
	/// Replaces the Toolbar commands (View menu).
	case toolbar
	/// Replaces the Sidebar commands (View menu).
	case sidebar
	/// Replaces the Window Size commands (Window menu).
	case windowSize
	/// Replaces the single-window list commands (Window menu).
	case singleWindowList
	/// Replaces the Help commands (Help menu).
	case help
	/// Replaces text formatting commands.
	case textFormatting

	/// App-info commands live in the Help menu until backend app-menu support exists.
	public static var appInfo: CommandGroupPlacement { .help }
}

// MARK: - CommandMenuItem

/// A single command menu item with label, action, shortcut, and enable state.
///
/// Used inside `CommandGroup` to declare menu items.
/// Separate from `MenuElement` (which is for in-view popup/context menus).
public struct CommandMenuItem {
	public let label: String
	public let action: () -> Void
	public let shortcut: KeyboardShortcut?
	public private(set) var isDisabled: Bool

	public init(
		_ label: String,
		shortcut: KeyboardShortcut? = nil,
		action: @escaping () -> Void
	) {
		self.label = label
		self.action = action
		self.shortcut = shortcut
		self.isDisabled = false
	}

	/// Returns a copy with disabled state set.
	public func disabled(_ isDisabled: Bool) -> CommandMenuItem {
		var copy = self
		copy.isDisabled = isDisabled
		return copy
	}
}

/// A native top-level command-menu section after SwiftUI command placements
/// have been mapped onto platform menu names.
public struct CommandMenuSection {
	public let title: String
	public let items: [CommandMenuItem]

	public init(title: String, items: [CommandMenuItem]) {
		self.title = title
		self.items = items
	}
}

/// Converts extracted command groups into deterministic native menu sections.
public func commandMenuSections(
	from groups: [CommandGroupPlacement: [CommandMenuItem]]
) -> [CommandMenuSection] {
	var sections: [CommandMenuSection] = []
	for (placement, items) in groups.sorted(by: commandPlacementComesBefore) {
		let title = commandMenuTitle(for: placement)
		if let existingIndex = sections.firstIndex(where: { $0.title == title }) {
			let existing = sections[existingIndex]
			sections[existingIndex] = CommandMenuSection(
				title: existing.title,
				items: existing.items + items
			)
		} else {
			sections.append(CommandMenuSection(title: title, items: items))
		}
	}
	return sections.filter { !$0.items.isEmpty }
}

private func commandMenuTitle(for placement: CommandGroupPlacement) -> String {
	switch placement {
	case .menu(let title):
		return title
	case .newItem, .appSettings, .saveItem, .printItem:
		return "File"
	case .undoRedo, .pasteboard, .textFormatting:
		return "Edit"
	case .toolbar, .sidebar:
		return "View"
	case .windowSize, .singleWindowList:
		return "Window"
	case .help:
		return "Help"
	}
}

private func commandPlacementComesBefore(
	_ lhs: (key: CommandGroupPlacement, value: [CommandMenuItem]),
	_ rhs: (key: CommandGroupPlacement, value: [CommandMenuItem])
) -> Bool {
	let lhsKey = commandPlacementSortKey(lhs.key)
	let rhsKey = commandPlacementSortKey(rhs.key)
	if lhsKey.rank != rhsKey.rank {
		return lhsKey.rank < rhsKey.rank
	}
	return lhsKey.tieBreak < rhsKey.tieBreak
}

private func commandPlacementSortKey(_ placement: CommandGroupPlacement) -> (rank: Int, tieBreak: String) {
	switch placement {
	case .newItem:
		return (0, "newItem")
	case .appSettings:
		return (1, "appSettings")
	case .saveItem:
		return (2, "saveItem")
	case .printItem:
		return (3, "printItem")
	case .undoRedo:
		return (10, "undoRedo")
	case .pasteboard:
		return (11, "pasteboard")
	case .textFormatting:
		return (12, "textFormatting")
	case .toolbar:
		return (20, "toolbar")
	case .sidebar:
		return (21, "sidebar")
	case .menu(let title):
		switch title {
		case "File":
			return (4, title)
		case "Edit":
			return (13, title)
		case "View":
			return (22, title)
		case "Capture":
			return (30, title)
		case "Window":
			return (79, title)
		case "Help":
			return (91, title)
		default:
			return (40, title)
		}
	case .windowSize:
		return (80, "windowSize")
	case .singleWindowList:
		return (81, "singleWindowList")
	case .help:
		return (90, "help")
	}
}

// MARK: - CommandGroup

/// A group of menu commands at a specific placement in the menu bar.
public struct CommandGroup: Commands {
	public typealias Body = Never

	public let placement: CommandGroupPlacement
	public let items: [CommandMenuItem]

	public init(
		replacing placement: CommandGroupPlacement,
		@CommandMenuBuilder content: () -> [CommandMenuItem]
	) {
		self.placement = placement
		self.items = content()
	}

	public init(
		before placement: CommandGroupPlacement,
		@CommandMenuBuilder content: () -> [CommandMenuItem]
	) {
		self.init(replacing: placement, content: content)
	}

	public init(
		after placement: CommandGroupPlacement,
		@CommandMenuBuilder content: () -> [CommandMenuItem]
	) {
		self.init(replacing: placement, content: content)
	}

	public var body: Never { fatalError() }
}

public struct CommandMenu: Commands {
	public typealias Body = Never

	public let title: String
	public let items: [CommandMenuItem]

	public init(_ title: String, @CommandMenuBuilder content: () -> [CommandMenuItem]) {
		self.title = title
		self.items = content()
	}

	public var body: Never { fatalError() }
}

public struct CommandCollection: Commands {
	public typealias Body = Never
	public let commands: [any Commands]

	public init(_ commands: [any Commands]) {
		self.commands = commands
	}

	public var body: Never { fatalError() }
}

// MARK: - TupleCommands

/// A composite commands type holding two children.
public struct TupleCommands<C0: Commands, C1: Commands>: Commands {
	public typealias Body = Never
	public let commands0: C0
	public let commands1: C1

	public init(_ c0: C0, _ c1: C1) {
		self.commands0 = c0
		self.commands1 = c1
	}

	public var body: Never { fatalError() }
}

// MARK: - CommandsBuilder

/// Result builder for composing Commands types.
@resultBuilder
public struct CommandsBuilder {
	public static func buildBlock<C: Commands>(_ content: C) -> C {
		content
	}

	public static func buildBlock<C0: Commands, C1: Commands>(_ c0: C0, _ c1: C1) -> TupleCommands<C0, C1> {
		TupleCommands(c0, c1)
	}

	public static func buildBlock<C0: Commands, C1: Commands, C2: Commands>(
		_ c0: C0, _ c1: C1, _ c2: C2
	) -> TupleCommands<TupleCommands<C0, C1>, C2> {
		TupleCommands(TupleCommands(c0, c1), c2)
	}

	public static func buildBlock<C0: Commands, C1: Commands, C2: Commands, C3: Commands>(
		_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3
	) -> TupleCommands<TupleCommands<TupleCommands<C0, C1>, C2>, C3> {
		TupleCommands(TupleCommands(TupleCommands(c0, c1), c2), c3)
	}

	public static func buildBlock<C0: Commands, C1: Commands, C2: Commands, C3: Commands, C4: Commands>(
		_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4
	) -> TupleCommands<TupleCommands<TupleCommands<TupleCommands<C0, C1>, C2>, C3>, C4> {
		TupleCommands(TupleCommands(TupleCommands(TupleCommands(c0, c1), c2), c3), c4)
	}

	public static func buildBlock<C0: Commands, C1: Commands, C2: Commands, C3: Commands, C4: Commands, C5: Commands>(
		_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5
	) -> TupleCommands<TupleCommands<TupleCommands<TupleCommands<TupleCommands<C0, C1>, C2>, C3>, C4>, C5> {
		TupleCommands(TupleCommands(TupleCommands(TupleCommands(TupleCommands(c0, c1), c2), c3), c4), c5)
	}

	@_disfavoredOverload
	public static func buildBlock(_ components: any Commands...) -> CommandCollection {
		CommandCollection(components)
	}

	public static func buildOptional(_ component: CommandCollection?) -> CommandCollection {
		component ?? CommandCollection([])
	}

	public static func buildOptional<C: Commands>(_ component: C?) -> CommandCollection {
		if let component {
			return CommandCollection([component])
		}
		return CommandCollection([])
	}

	public static func buildEither(first component: CommandCollection) -> CommandCollection {
		component
	}

	public static func buildEither(second component: CommandCollection) -> CommandCollection {
		component
	}

	public static func buildEither<C: Commands>(first component: C) -> CommandCollection {
		CommandCollection([component])
	}

	public static func buildEither<C: Commands>(second component: C) -> CommandCollection {
		CommandCollection([component])
	}
}

// MARK: - CommandMenuBuilder

@MainActor
private protocol CommandMenuButtonRepresentable {
	var commandMenuButtonLabel: String { get }
	var commandMenuButtonAction: () -> Void { get }
}

extension Button: CommandMenuButtonRepresentable {
	var commandMenuButtonLabel: String { commandMenuTextLabel(from: label) }
	var commandMenuButtonAction: () -> Void { action }
}

@MainActor
private protocol CommandMenuShortcutRepresentable {
	var commandMenuShortcutContent: any View { get }
	var commandMenuShortcut: KeyboardShortcut { get }
}

extension KeyboardShortcutView: CommandMenuShortcutRepresentable {
	var commandMenuShortcutContent: any View { content }
	var commandMenuShortcut: KeyboardShortcut { shortcut }
}

@MainActor
private protocol CommandMenuDisabledRepresentable {
	var commandMenuDisabledContent: any View { get }
	var commandMenuIsDisabled: Bool { get }
}

extension DisabledView: CommandMenuDisabledRepresentable {
	var commandMenuDisabledContent: any View { content }
	var commandMenuIsDisabled: Bool { isDisabled }
}

@MainActor
private protocol CommandMenuWrappedViewRepresentable {
	var commandMenuWrappedContent: any View { get }
}

@MainActor
private protocol CommandMenuConditionalRepresentable {
	var commandMenuActiveContent: any View { get }
}

extension _ConditionalView: CommandMenuConditionalRepresentable {
	var commandMenuActiveContent: any View {
		switch self {
		case .trueContent(let content):
			return content
		case .falseContent(let content):
			return content
		}
	}
}

@MainActor
private protocol CommandMenuOptionalRepresentable {
	var commandMenuOptionalContent: (any View)? { get }
}

extension Optional: CommandMenuOptionalRepresentable where Wrapped: View {
	var commandMenuOptionalContent: (any View)? {
		switch self {
		case .some(let content):
			return content
		case .none:
			return nil
		}
	}
}

extension LineLimitView: CommandMenuWrappedViewRepresentable {
	var commandMenuWrappedContent: any View { content }
}

extension FrameView: CommandMenuWrappedViewRepresentable {
	var commandMenuWrappedContent: any View { content }
}

extension FontModifiedView: CommandMenuWrappedViewRepresentable {
	var commandMenuWrappedContent: any View { content }
}

extension ForegroundColorView: CommandMenuWrappedViewRepresentable {
	var commandMenuWrappedContent: any View { content }
}

extension HelpView: CommandMenuWrappedViewRepresentable {
	var commandMenuWrappedContent: any View { content }
}

extension PaddedView: CommandMenuWrappedViewRepresentable {
	var commandMenuWrappedContent: any View { content }
}

extension OpacityView: CommandMenuWrappedViewRepresentable {
	var commandMenuWrappedContent: any View { content }
}

extension OffsetView: CommandMenuWrappedViewRepresentable {
	var commandMenuWrappedContent: any View { content }
}

extension ScaleEffectView: CommandMenuWrappedViewRepresentable {
	var commandMenuWrappedContent: any View { content }
}

extension AnimatedView: CommandMenuWrappedViewRepresentable {
	var commandMenuWrappedContent: any View { content }
}

extension BackgroundView: CommandMenuWrappedViewRepresentable {
	var commandMenuWrappedContent: any View { content }
}

extension OverlayView: CommandMenuWrappedViewRepresentable {
	var commandMenuWrappedContent: any View { content }
}

extension CornerRadiusView: CommandMenuWrappedViewRepresentable {
	var commandMenuWrappedContent: any View { content }
}

extension ClipShapeView: CommandMenuWrappedViewRepresentable {
	var commandMenuWrappedContent: any View { content }
}

extension ClippedView: CommandMenuWrappedViewRepresentable {
	var commandMenuWrappedContent: any View { content }
}

extension LayoutPriorityView: CommandMenuWrappedViewRepresentable {
	var commandMenuWrappedContent: any View { content }
}

extension FixedSizeView: CommandMenuWrappedViewRepresentable {
	var commandMenuWrappedContent: any View { content }
}

extension ButtonStyleModifier: CommandMenuWrappedViewRepresentable {
	var commandMenuWrappedContent: any View { content }
}

extension CustomButtonStyleModifier: CommandMenuWrappedViewRepresentable {
	var commandMenuWrappedContent: any View { content }
}

extension LabelsHiddenView: CommandMenuWrappedViewRepresentable {
	var commandMenuWrappedContent: any View { content }
}

@MainActor
private func commandMenuTextLabel(from view: any View) -> String {
	if let text = view as? Text {
		return text.content
	}
	if let label = view as? any AnyLabelView {
		return label.title
	}
	if let wrapped = view as? any CommandMenuWrappedViewRepresentable {
		return commandMenuTextLabel(from: wrapped.commandMenuWrappedContent)
	}
	if let shortcut = view as? any CommandMenuShortcutRepresentable {
		return commandMenuTextLabel(from: shortcut.commandMenuShortcutContent)
	}
	if let disabled = view as? any CommandMenuDisabledRepresentable {
		return commandMenuTextLabel(from: disabled.commandMenuDisabledContent)
	}
	if let conditional = view as? any CommandMenuConditionalRepresentable {
		return commandMenuTextLabel(from: conditional.commandMenuActiveContent)
	}
	if let optional = view as? any CommandMenuOptionalRepresentable {
		guard let content = optional.commandMenuOptionalContent else { return "" }
		return commandMenuTextLabel(from: content)
	}
	if let multi = view as? MultiChildView {
		for child in multi.children {
			let label = commandMenuTextLabel(from: child)
			if !label.isEmpty {
				return label
			}
		}
	}
	return ""
}

@MainActor
private func commandMenuItems(from view: any View) -> [CommandMenuItem] {
	if let button = view as? any CommandMenuButtonRepresentable {
		return [CommandMenuItem(button.commandMenuButtonLabel, action: button.commandMenuButtonAction)]
	}
	if let shortcut = view as? any CommandMenuShortcutRepresentable {
		return commandMenuItems(from: shortcut.commandMenuShortcutContent)
			.map { commandMenuItem($0, shortcut: shortcut.commandMenuShortcut) }
	}
	if let disabled = view as? any CommandMenuDisabledRepresentable {
		return commandMenuItems(from: disabled.commandMenuDisabledContent)
			.map { $0.disabled(disabled.commandMenuIsDisabled || $0.isDisabled) }
	}
	if let wrapped = view as? any CommandMenuWrappedViewRepresentable {
		return commandMenuItems(from: wrapped.commandMenuWrappedContent)
	}
	if let conditional = view as? any CommandMenuConditionalRepresentable {
		return commandMenuItems(from: conditional.commandMenuActiveContent)
	}
	if let optional = view as? any CommandMenuOptionalRepresentable {
		guard let content = optional.commandMenuOptionalContent else { return [] }
		return commandMenuItems(from: content)
	}
	if let multi = view as? MultiChildView {
		return multi.children.flatMap(commandMenuItems)
	}
	return []
}

private func commandMenuItem(_ item: CommandMenuItem, shortcut: KeyboardShortcut) -> CommandMenuItem {
	CommandMenuItem(
		item.label,
		shortcut: item.shortcut ?? shortcut,
		action: item.action
	)
	.disabled(item.isDisabled)
}

/// Result builder for composing CommandMenuItem arrays.
@resultBuilder
public struct CommandMenuBuilder {
	public static func buildBlock(_ items: [CommandMenuItem]...) -> [CommandMenuItem] {
		items.flatMap { $0 }
	}

	public static func buildExpression(_ item: CommandMenuItem) -> [CommandMenuItem] {
		[item]
	}

	// Keep this disfavored so explicit CommandMenuItem expressions win, while
	// Apple's CommandMenu { Button(...).keyboardShortcut(...) } spelling still
	// lowers into backend command items.
	@_disfavoredOverload
	@MainActor
	public static func buildExpression<V: View>(_ view: V) -> [CommandMenuItem] {
		commandMenuItems(from: view)
	}

	public static func buildOptional(_ items: [CommandMenuItem]?) -> [CommandMenuItem] {
		items ?? []
	}

	public static func buildEither(first items: [CommandMenuItem]) -> [CommandMenuItem] {
		items
	}

	public static func buildEither(second items: [CommandMenuItem]) -> [CommandMenuItem] {
		items
	}
}

// MARK: - Command extraction

/// Extract all CommandMenuItems from a Commands tree, grouped by placement.
public func extractCommandGroups<C: Commands>(from commands: C) -> [CommandGroupPlacement: [CommandMenuItem]] {
	var result: [CommandGroupPlacement: [CommandMenuItem]] = [:]
	collectCommandGroups(commands, into: &result)
	return result
}

/// Protocol for extracting command groups from tuple commands.
protocol TupleCommandsProtocol {
	func collectInto(_ result: inout [CommandGroupPlacement: [CommandMenuItem]])
}

extension TupleCommands: TupleCommandsProtocol {
	func collectInto(_ result: inout [CommandGroupPlacement: [CommandMenuItem]]) {
		collectCommandGroups(commands0, into: &result)
		collectCommandGroups(commands1, into: &result)
	}
}

extension CommandCollection: TupleCommandsProtocol {
	func collectInto(_ result: inout [CommandGroupPlacement: [CommandMenuItem]]) {
		for command in commands {
			collectKnownCommand(command, into: &result)
		}
	}
}

extension Group: TupleCommandsProtocol where Content: Commands {
	func collectInto(_ result: inout [CommandGroupPlacement: [CommandMenuItem]]) {
		collectCommandGroups(content, into: &result)
	}
}

private func collectKnownCommand(_ command: any Commands, into result: inout [CommandGroupPlacement: [CommandMenuItem]]) {
	if let group = command as? CommandGroup {
		result[group.placement, default: []].append(contentsOf: group.items)
	} else if let menu = command as? CommandMenu {
		result[.menu(menu.title), default: []].append(contentsOf: menu.items)
	} else if let tuple = command as? TupleCommandsProtocol {
		tuple.collectInto(&result)
	}
}

private func collectCommandGroups<C: Commands>(_ commands: C, into result: inout [CommandGroupPlacement: [CommandMenuItem]]) {
	if let group = commands as? CommandGroup {
		result[group.placement, default: []].append(contentsOf: group.items)
	} else if let menu = commands as? CommandMenu {
		result[.menu(menu.title), default: []].append(contentsOf: menu.items)
	} else if let tuple = commands as? TupleCommandsProtocol {
		tuple.collectInto(&result)
	} else if !(commands is EmptyCommands) {
		// Recurse into body for custom Commands types
		let body = commands.body
		collectCommandGroups(body, into: &result)
	}
}

// MARK: - Scene commands modifier

/// Type-erased commands factory closure.
public typealias AnyCommandsFactory = () -> [CommandGroupPlacement: [CommandMenuItem]]

/// Global storage for the commands factory.
/// Set by `.commands {}` on WindowGroup. Backends read this
/// after window creation to build the native menu bar.
///
/// Single-slot design: one app has one set of commands.
/// Multiple WindowGroups share the same command definitions.
public var globalCommandsFactory: AnyCommandsFactory?

private func commandsDebugLog(_ message: String) {
	#if canImport(Foundation)
	guard ProcessInfo.processInfo.environment["QUILLUI_GTK_DEBUG_ACTIONS"] == "1" else {
		return
	}
	if let data = ("[QuillUI GTK] " + message + "\n").data(using: .utf8) {
		FileHandle.standardError.write(data)
	}
	#endif
}

extension WindowGroup {
	/// Attaches app-level menu commands to this window group.
	public func commands<C: Commands>(@CommandsBuilder _ commands: @escaping () -> C) -> WindowGroup {
		commandsDebugLog("installed commands factory type=\(C.self)")
		globalCommandsFactory = {
			let commandTree = commands()
			let groups = extractCommandGroups(from: commandTree)
			let itemCount = groups.values.reduce(0) { $0 + $1.count }
			commandsDebugLog("commands factory invoked type=\(C.self) placements=\(groups.count) items=\(itemCount)")
			return groups
		}
		return self
	}
}

public extension Scene {
	/// Attaches app-level menu commands to any scene-like value.
	func commands<C: Commands>(@CommandsBuilder _ commands: @escaping () -> C) -> Self {
		commandsDebugLog("installed commands factory type=\(C.self)")
		globalCommandsFactory = {
			let commandTree = commands()
			let groups = extractCommandGroups(from: commandTree)
			let itemCount = groups.values.reduce(0) { $0 + $1.count }
			commandsDebugLog("commands factory invoked type=\(C.self) placements=\(groups.count) items=\(itemCount)")
			return groups
		}
		return self
	}
}
