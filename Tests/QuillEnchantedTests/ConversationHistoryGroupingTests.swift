import Foundation
import Testing
@testable import QuillEnchantedCore

@Suite("Enchanted conversation history grouping")
@MainActor
struct ConversationHistoryGroupingTests {
    @Test("groups by calendar day, sorts newest first, and formats relative dates")
    func groupsByDayNewestFirstAndFormatsRelativeDates() throws {
        let calendar = utcCalendar()
        let referenceDate = try date(year: 2026, month: 6, day: 1, hour: 12, calendar: calendar)
        let todayStart = calendar.startOfDay(for: referenceDate)
        let yesterday = try date(year: 2026, month: 5, day: 31, hour: 16, calendar: calendar)
        let older = try date(year: 2026, month: 5, day: 28, hour: 9, calendar: calendar)

        let conversations = [
            ConversationSummary(id: "yesterday", title: "Yesterday", updatedAt: yesterday),
            ConversationSummary(id: "older", title: "Older", updatedAt: older),
            ConversationSummary(
                id: "today-evening",
                title: "Today evening",
                updatedAt: try date(year: 2026, month: 6, day: 1, hour: 21, calendar: calendar)
            ),
            ConversationSummary(
                id: "today-morning",
                title: "Today morning",
                updatedAt: try date(year: 2026, month: 6, day: 1, hour: 8, calendar: calendar)
            )
        ]

        let groups = EnchantedConversationHistory.groups(conversations: conversations, calendar: calendar)

        #expect(groups.map(\.date) == [
            todayStart,
            calendar.startOfDay(for: yesterday),
            calendar.startOfDay(for: older)
        ])
        #expect(groups[0].conversations.map(\.id) == ["today-evening", "today-morning"])
        #expect(groups[1].conversations.map(\.id) == ["yesterday"])
        #expect(groups[2].conversations.map(\.id) == ["older"])
        #expect(
            EnchantedConversationHistory.relativeDayTitle(
                for: groups[0].date,
                referenceDate: referenceDate,
                calendar: calendar
            ) == EnchantedCopy.todayTitle
        )
        #expect(
            EnchantedConversationHistory.relativeDayTitle(
                for: groups[1].date,
                referenceDate: referenceDate,
                calendar: calendar
            ) == EnchantedCopy.yesterdayTitle
        )
        #expect(
            EnchantedConversationHistory.relativeDayTitle(
                for: groups[2].date,
                referenceDate: referenceDate,
                calendar: calendar
            ) == "4 days ago"
        )
    }

    @Test("model deletes all conversations updated on a selected day")
    func modelDeletesDailyConversations() throws {
        let calendar = utcCalendar()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let context = try EnchantedModelContext.quillData(url: url)
        let todayOne = try context.insert(ConversationDraft(title: "Today one"))
        let todayTwo = try context.insert(ConversationDraft(title: "Today two"))
        let yesterday = try context.insert(ConversationDraft(title: "Yesterday"))
        let todayDate = try date(year: 2026, month: 6, day: 1, hour: 10, calendar: calendar)

        try context.insert(ChatMessage(conversationID: todayOne.id, role: .user, content: "A", createdAt: todayDate))
        try context.insert(ChatMessage(
            conversationID: todayTwo.id,
            role: .user,
            content: "B",
            createdAt: try date(year: 2026, month: 6, day: 1, hour: 22, calendar: calendar)
        ))
        try context.insert(ChatMessage(
            conversationID: yesterday.id,
            role: .user,
            content: "C",
            createdAt: try date(year: 2026, month: 5, day: 31, hour: 10, calendar: calendar)
        ))

        let model = EnchantedModel(endpoint: "http://localhost:11434", modelContext: context)
        model.conversations = try context.fetchConversations()
        model.selectedConversationID = todayOne.id

        model.deleteDailyConversations(on: todayDate, calendar: calendar)

        #expect(model.conversations.map(\.id) == [yesterday.id])
        #expect(model.selectedConversationID == yesterday.id)
        #expect(try context.fetchConversations().map(\.id) == [yesterday.id])
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        calendar: Calendar
    ) throws -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return try #require(calendar.date(from: components))
    }
}
