//
//  ActivityLogViewModel.swift
//  ActivityLog
//
//  Shared presentation model for NetNewsWire activity log views.
//

import Foundation

public enum ActivityLogTextColor: Equatable, Sendable {
	case primary
	case secondary
	case success
	case failure
	case account(accountID: String?)
}

public enum ActivityLogTextWeight: Equatable, Sendable {
	case regular
	case medium
	case bold
}

public struct ActivityLogTextSegment: Equatable, Sendable {
	public let text: String
	public let color: ActivityLogTextColor
	public let weight: ActivityLogTextWeight

	public init(text: String, color: ActivityLogTextColor, weight: ActivityLogTextWeight) {
		self.text = text
		self.color = color
		self.weight = weight
	}
}

@MainActor public final class ActivityLogViewModel {

	public static func segments(for activity: Activity) -> [ActivityLogTextSegment] {
		var result = [ActivityLogTextSegment]()

		let date = activity.endDate ?? Date()
		result.append(ActivityLogTextSegment(text: "[\(activityLogTimestampFormatter.string(from: date))] ", color: .secondary, weight: .regular))

		let isFailed = activity.state == .failed
		let indicator = isFailed ? "✗ " : "✓ "
		result.append(ActivityLogTextSegment(text: indicator, color: isFailed ? .failure : .success, weight: .bold))

		let ownerColor = ownerColor(for: activity.owner)
		result.append(ActivityLogTextSegment(text: "\(activity.owner.displayName): ", color: ownerColor, weight: .medium))
		result.append(ActivityLogTextSegment(text: activity.kind.displayName(detail: activity.detail), color: ownerColor, weight: .medium))

		if let detail = secondaryDetail(for: activity) {
			result.append(ActivityLogTextSegment(text: " \(detail)", color: .secondary, weight: .regular))
		}

		if let formattedDuration = activity.formattedDuration {
			result.append(ActivityLogTextSegment(text: " (\(formattedDuration))", color: .secondary, weight: .regular))
		}

		if let message = activity.completionMessage {
			result.append(ActivityLogTextSegment(text: " — \(message)", color: .secondary, weight: .regular))
		}

		if isFailed, let error = activity.error {
			result.append(ActivityLogTextSegment(text: " — \(error.localizedDescription)", color: .failure, weight: .regular))
		}

		return result
	}
}

private extension ActivityLogViewModel {

	static var activityLogTimestampFormatter: DateFormatter {
		let formatter = DateFormatter()
		formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
		formatter.locale = Locale(identifier: "en_US_POSIX")
		return formatter
	}

	static func ownerColor(for owner: ActivityOwner) -> ActivityLogTextColor {
		switch owner {
		case .account(let accountID, _):
			return .account(accountID: accountID)
		case .app, .feedFinder, .feedImageDownloader, .faviconDownloader, .avatarDownloader, .htmlMetadataDownloader:
			return .secondary
		}
	}

	static func secondaryDetail(for activity: Activity) -> String? {
		switch activity.kind {
		case .refreshFeedContent(let feedURL):
			return activity.detail == nil ? nil : feedURL
		case .downloadHTMLMetadata:
			guard let detail = activity.detail else {
				return nil
			}
			let format = NSLocalizedString("(last downloaded %@)", bundle: .module, comment: "Activity log - when HTML metadata for a URL was last downloaded - %@ is a date")
			return String(format: format, detail)
		default:
			return activity.detail
		}
	}
}
