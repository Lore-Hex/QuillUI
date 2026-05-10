import Foundation
import Testing
import QuillData

@Suite("Exhaustive Predicate Matrix")
struct ExhaustivePredicateTests {

    @Test("Basic logical matrix")
    func logicMatrix() {
        #expect((#QuillPredicate<FuzzUser> { $0.age > 10 }).sqlFilter == "(age > 10)")
        #expect((#QuillPredicate<FuzzUser> { $0.age <= 20 }).sqlFilter == "(age <= 20)")
        #expect((#QuillPredicate<FuzzUser> { $0.name == "Alice" }).sqlFilter == "(name = 'Alice')")
        #expect((#QuillPredicate<FuzzUser> { $0.name != "Bob" }).sqlFilter == "(name != 'Bob')")
        #expect((#QuillPredicate<FuzzUser> { $0.isActive == true }).sqlFilter == "(isActive = 1)")
        #expect((#QuillPredicate<FuzzUser> { $0.isActive == false }).sqlFilter == "(isActive = 0)")
    }

    @Test("Optional & Nil matrix")
    func nilMatrix() {
        #expect((#QuillPredicate<FuzzUser> { $0.id == nil }).sqlFilter == "(id IS NULL)")
        #expect((#QuillPredicate<FuzzUser> { $0.id != nil }).sqlFilter == "(id IS NOT NULL)")
        #expect((#QuillPredicate<FuzzUser> { ($0.id ?? "none") == "none" }).sqlFilter == "(COALESCE(id, 'none') = 'none')")
    }

    @Test("String methods matrix")
    func stringMatrix() {
        #expect((#QuillPredicate<FuzzUser> { $0.name.contains("a") }).sqlFilter == "(name LIKE '%' || 'a' || '%')")
        #expect((#QuillPredicate<FuzzUser> { $0.name.hasPrefix("S") }).sqlFilter == "(name LIKE 'S' || '%')")
        #expect((#QuillPredicate<FuzzUser> { $0.name.hasSuffix("z") }).sqlFilter == "(name LIKE '%' || 'z')")
        #expect((#QuillPredicate<FuzzUser> { $0.name.isEmpty }).sqlFilter == "(LENGTH(name) = 0)")
        #expect((#QuillPredicate<FuzzUser> { !$0.name.isEmpty }).sqlFilter == "NOT ((LENGTH(name) = 0))")
    }

    @Test("Compound logic matrix")
    func compoundMatrix() {
        #expect((#QuillPredicate<FuzzUser> { $0.age > 18 && $0.isActive }).sqlFilter == "((age > 18) AND isActive)")
        #expect((#QuillPredicate<FuzzUser> { $0.age < 5 || $0.age > 65 }).sqlFilter == "((age < 5) OR (age > 65))")
        #expect((#QuillPredicate<FuzzUser> { ($0.age > 10 && $0.name == "A") || $0.isActive }).sqlFilter == "(((age > 10) AND (name = 'A')) OR isActive)")
    }

    @Test("Optional chaining and forced unwrap matrix")
    func navigationMatrix() {
        #expect((#QuillPredicate<FuzzUser> { $0.profile?.bio == "test" }).sqlFilter == "(profile_bio = 'test')")
        #expect((#QuillPredicate<FuzzUser> { $0.profile!.bio == "test" }).sqlFilter == "(profile_bio = 'test')")
    }
}

@QuillModel
public final class FuzzProfile: Identifiable, @unchecked Sendable {
    public var id: UUID
    public var bio: String

    public init(id: UUID, bio: String) {
        self.id = id
        self.bio = bio
    }
}

@QuillModel
public final class FuzzUser: Identifiable, @unchecked Sendable {
    public var id: String?
    public var name: String
    public var age: Int
    public var isActive: Bool
    public var profile: FuzzProfile?

    public init(id: String?, name: String, age: Int, isActive: Bool, profile: FuzzProfile? = nil) {
        self.id = id
        self.name = name
        self.age = age
        self.isActive = isActive
        self.profile = profile
    }
}
