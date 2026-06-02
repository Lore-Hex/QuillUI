//
//  NetworkMonitor.swift
//  RSWeb
//
//  Created by Brent Simmons on 11/4/25.
//

import Foundation
import QuillRSCoreShim

// NetworkMonitor is Apple-only — it leans on NWPathMonitor /
// NWPath / NWInterface which are part of Apple's Network
// framework. Quill's in-tree Sources/Network shim only covers
// the symbols Enchanted needed; NWPathMonitor isn't one of
// them. Rather than stand up an entire NWPathMonitor analog
// on top of /proc/net or NetworkManager DBus, we ship a
// Darwin-only implementation and stub the public surface to
// "always connected, no metadata" on Linux. NetNewsWire's
// production code doesn't actually consume this monitor today
// (no production call sites in the vendored RSWeb / FeedFinder
// graph); it's here for future code that asks. Nothing
// downstream observes the stub values.

#if canImport(Darwin)
import Network
import os

nonisolated public final class NetworkMonitor: Sendable {
	public static let shared = NetworkMonitor()

	private let monitor: NWPathMonitor
	private let queue = DispatchQueue(label: "RSWeb NetworkMonitor")

	private struct State: Sendable {
		var isConnected = false
		var connectionType: NWInterface.InterfaceType?
		var isExpensive = false
		var isConstrained = false
	}

	private let state = OSAllocatedUnfairLock<State>(initialState: State())

	public var isConnected: Bool {
		state.withLock { $0.isConnected }
	}

	public var connectionType: NWInterface.InterfaceType? {
		state.withLock { $0.connectionType }
	}

	/// Is the connection expensive (cellular data with limited plan, for instance)
	public var isExpensive: Bool {
		state.withLock { $0.isExpensive }
	}

	/// Is the connection constrained (Low Data Mode enabled, for instance)
	public var isConstrained: Bool {
		state.withLock { $0.isConstrained }
	}

	@MainActor private var monitorIsActive = false

	private init() {
		monitor = NWPathMonitor()

		monitor.pathUpdateHandler = { [weak self] path in
			self?.updateStatus(with: path)
		}
	}

	@MainActor public func start() {
		guard !monitorIsActive else {
			assertionFailure("start called when already active")
			return
		}
		monitorIsActive = true
		monitor.start(queue: queue)
	}

	deinit {
		monitor.cancel()
	}

	private func updateStatus(with path: NWPath) {
		state.withLock { state in
			state.isConnected = path.status == .satisfied
			state.connectionType = path.availableInterfaces.first?.type
			state.isExpensive = path.isExpensive
			state.isConstrained = path.isConstrained
		}
	}
}
#else
/// Linux stub. Always-connected, no link metadata. Downstream
/// callers that need real link state on Linux will replace
/// this with a NetworkManager-DBus or /proc/net/route reader
/// when the use case actually arrives.
nonisolated public final class NetworkMonitor: Sendable {
	public static let shared = NetworkMonitor()
	public var isConnected: Bool { true }
	public var isExpensive: Bool { false }
	public var isConstrained: Bool { false }
	@MainActor public func start() {}
	private init() {}
}
#endif
