//
//  QuillRelationships.swift
//  QuillData
//
//  In-memory @Relationship inverse maintenance — SwiftData parity.
//
//  SwiftData keeps relationship inverses consistent in memory, instantly,
//  before any save: assigning the to-one side (`child.parent = p`) is
//  immediately reflected in the to-many inverse (`p.children`), and vice
//  versa. QuillData models are plain reference types whose `@Relationship`
//  properties are ordinary stored `var`s, so without this runtime the
//  inverse is never populated and app code that reads `p.children` after
//  assigning `child.parent` (a very common SwiftData pattern) sees stale or
//  empty data.
//
//  This file provides:
//    1. A process-wide registry of inverse relationship pairs, keyed by
//       (model type, property name). It is populated either explicitly
//       (tests) or by lowering-injected registration (generated apps).
//    2. `relationshipDidSet`, the hook the `@Relationship` accessor macro
//       emits in a `didSet`. The OUTERMOST set performs every inverse
//       update directly; re-entrant sets triggered by those updates are
//       suppressed, which both prevents infinite cascades and keeps the two
//       sides consistent.
//    3. `encodingWithoutToManyCycles`, used by the SQLite store so that a
//       populated to-many inverse (parent.children -> child.parent ->
//       parent ...) does not make the synthesized `Codable` encoder recurse
//       forever. To-many collections are derivable from the persisted
//       to-one foreign side, so they are temporarily cleared (without firing
//       maintenance) around encoding and restored afterwards. When no
//       inverse is registered this is a zero-overhead pass-through.
//
//  Inverse maintenance is meaningful only for reference types; the accessor
//  macro therefore emits the `didSet` only for `@Relationship` properties
//  declared on a `class`.
//

import Foundation

public enum QuillRelationships {

    // MARK: - Re-entrancy / encode suppression (per thread)

    private static let suppressKey = "com.quill.quilldata.suppressRelationshipMaintenance"

    /// While true, `relationshipDidSet` returns immediately. Set around the
    /// application of an inverse update (so the resulting `didSet`s on the
    /// other side do not cascade) and around encode-time clearing.
    static var isSuppressed: Bool {
        get { (Thread.current.threadDictionary[suppressKey] as? Bool) ?? false }
        set { Thread.current.threadDictionary[suppressKey] = newValue }
    }

    // MARK: - Registry

    private struct Key: Hashable {
        let type: ObjectIdentifier
        let property: String
    }

    /// Handlers for the to-ONE side of a pair (e.g. `Message.conversation`).
    /// They mutate the to-many inverse collection on the related parent.
    private struct ToOneInverse {
        let addToInverse: (_ child: AnyObject, _ parent: AnyObject) -> Void
        let removeFromInverse: (_ child: AnyObject, _ parent: AnyObject) -> Void
    }

    /// Handlers for the to-MANY side of a pair (e.g. `Conversation.messages`).
    /// They mutate the to-one inverse reference on each element, and support
    /// the encode-time clear/restore of the collection.
    private struct ToManyInverse {
        let setElementOwner: (_ element: AnyObject, _ owner: AnyObject?) -> Void
        let elementOwnerIsSame: (_ element: AnyObject, _ owner: AnyObject) -> Bool
        let currentElements: (_ owner: AnyObject) -> [AnyObject]
        let clear: (_ owner: AnyObject) -> [AnyObject]
        let restore: (_ owner: AnyObject, _ saved: [AnyObject]) -> Void
    }

    // All mutable state below is guarded by `lock`; `nonisolated(unsafe)`
    // tells the Swift 6 concurrency checker that synchronization is external.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var toOneInverses: [Key: ToOneInverse] = [:]
    nonisolated(unsafe) private static var toManyInverses: [Key: ToManyInverse] = [:]
    /// Per-type getters for every to-one relationship, used to walk the
    /// object graph during cycle-safe encoding.
    nonisolated(unsafe) private static var toOneGetters: [ObjectIdentifier: [(AnyObject) -> AnyObject?]] = [:]
    /// Fast-path flag: true once any to-many inverse exists.
    nonisolated(unsafe) private static var hasRegisteredToMany = false

    // MARK: - Registration

    /// Register a bidirectional inverse pair. A single call wires BOTH
    /// directions, so it is enough to register from the side that declares
    /// the `inverse:` key path (the SwiftData convention).
    ///
    /// - Parameters:
    ///   - parentType:     the to-many owner type (e.g. `ConversationSD.self`).
    ///   - toManyProperty: the to-many property name (e.g. `"messages"`).
    ///   - toMany:         writable key path to the to-many collection.
    ///   - childType:      the to-one owner type (e.g. `MessageSD.self`).
    ///   - toOneProperty:  the to-one property name (e.g. `"conversation"`).
    ///   - toOne:          writable key path to the to-one reference.
    public static func registerInverse<Parent: AnyObject, Child: AnyObject>(
        parentType: Parent.Type,
        toManyProperty: String,
        toMany toManyKeyPath: ReferenceWritableKeyPath<Parent, [Child]>,
        childType: Child.Type,
        toOneProperty: String,
        toOne toOneKeyPath: ReferenceWritableKeyPath<Child, Parent?>
    ) {
        let parentKey = Key(type: ObjectIdentifier(Parent.self), property: toManyProperty)
        let childKey = Key(type: ObjectIdentifier(Child.self), property: toOneProperty)

        let toOneInverse = ToOneInverse(
            addToInverse: { child, parent in
                guard let c = child as? Child, let p = parent as? Parent else { return }
                if !p[keyPath: toManyKeyPath].contains(where: { $0 === c }) {
                    p[keyPath: toManyKeyPath].append(c)
                }
            },
            removeFromInverse: { child, parent in
                guard let c = child as? Child, let p = parent as? Parent else { return }
                p[keyPath: toManyKeyPath].removeAll { $0 === c }
            }
        )

        let toManyInverse = ToManyInverse(
            setElementOwner: { element, owner in
                guard let e = element as? Child else { return }
                e[keyPath: toOneKeyPath] = owner as? Parent
            },
            elementOwnerIsSame: { element, owner in
                guard let e = element as? Child, let o = owner as? Parent else { return false }
                return e[keyPath: toOneKeyPath] === o
            },
            currentElements: { owner in
                guard let p = owner as? Parent else { return [] }
                return p[keyPath: toManyKeyPath]
            },
            clear: { owner in
                guard let p = owner as? Parent else { return [] }
                let saved = p[keyPath: toManyKeyPath]
                p[keyPath: toManyKeyPath] = []
                return saved
            },
            restore: { owner, saved in
                guard let p = owner as? Parent else { return }
                p[keyPath: toManyKeyPath] = saved.compactMap { $0 as? Child }
            }
        )

        lock.lock()
        toOneInverses[childKey] = toOneInverse
        toManyInverses[parentKey] = toManyInverse
        toOneGetters[ObjectIdentifier(Child.self), default: []].append { ($0 as? Child)?[keyPath: toOneKeyPath] }
        hasRegisteredToMany = true
        lock.unlock()
    }

    /// Remove all registrations. Intended for test isolation only.
    public static func _resetForTesting() {
        lock.lock()
        toOneInverses.removeAll()
        toManyInverses.removeAll()
        toOneGetters.removeAll()
        hasRegisteredToMany = false
        lock.unlock()
        isSuppressed = false
    }

    // MARK: - The didSet hook (emitted by the @Relationship accessor macro)

    /// Called from a `@Relationship` property's `didSet`. `ownerType` is the
    /// `ObjectIdentifier` of the enclosing class; `property` is the property
    /// name; `oldValue`/`newValue` are the observer's old and current values.
    public static func relationshipDidSet(
        _ owner: AnyObject,
        _ ownerType: ObjectIdentifier,
        _ property: String,
        oldValue: Any?,
        newValue: Any?
    ) {
        if isSuppressed { return }
        let key = Key(type: ownerType, property: property)

        lock.lock()
        let toOne = toOneInverses[key]
        let toMany = toManyInverses[key]
        lock.unlock()

        if toOne == nil && toMany == nil { return }

        // The outermost set applies every inverse update; updates we make
        // below re-enter this function via the other side's didSet, which is
        // suppressed so it returns immediately (no cascade, no recursion).
        isSuppressed = true
        defer { isSuppressed = false }

        if let toOne {
            // to-one side changed (e.g. message.conversation): refresh the
            // to-many inverse on the old and new parents.
            let oldParent = asObject(oldValue)
            let newParent = asObject(newValue)
            if let oldParent, oldParent !== newParent {
                toOne.removeFromInverse(owner, oldParent)
            }
            if let newParent {
                toOne.addToInverse(owner, newParent)
            }
        }

        if let toMany {
            // to-many side changed (e.g. conversation.messages): set the
            // to-one inverse on added elements, clear it on removed ones.
            let oldElements = asObjectArray(oldValue)
            let newElements = asObjectArray(newValue)
            for element in newElements where !oldElements.contains(where: { $0 === element }) {
                if !toMany.elementOwnerIsSame(element, owner) {
                    toMany.setElementOwner(element, owner)
                }
            }
            for element in oldElements where !newElements.contains(where: { $0 === element }) {
                if toMany.elementOwnerIsSame(element, owner) {
                    toMany.setElementOwner(element, nil)
                }
            }
        }
    }

    // MARK: - Cycle-safe encoding

    /// Run `body` (typically `JSONEncoder().encode(model)`) with every
    /// reachable to-many relationship temporarily emptied, so that a
    /// bidirectionally-populated graph does not make the synthesized
    /// `Codable` encoder recurse forever. The collections are restored
    /// afterwards. No-op fast path when nothing is registered.
    static func encodingWithoutToManyCycles<T>(_ root: any PersistentModel, _ body: () throws -> T) rethrows -> T {
        lock.lock()
        let active = hasRegisteredToMany
        lock.unlock()
        guard active else { return try body() }

        let previouslySuppressed = isSuppressed
        isSuppressed = true

        var saved: [(owner: AnyObject, property: String, elements: [AnyObject])] = []
        var visited = Set<ObjectIdentifier>()

        func walk(_ object: AnyObject) {
            let oid = ObjectIdentifier(object)
            if visited.contains(oid) { return }
            visited.insert(oid)
            let typeID = ObjectIdentifier(type(of: object))

            lock.lock()
            let toManyForType = toManyInverses.filter { $0.key.type == typeID }
            let getters = toOneGetters[typeID] ?? []
            lock.unlock()

            for (key, inverse) in toManyForType {
                for element in inverse.currentElements(object) { walk(element) }
                let elements = inverse.clear(object)
                saved.append((object, key.property, elements))
            }
            for getter in getters {
                if let related = getter(object) { walk(related) }
            }
        }

        walk(root as AnyObject)

        defer {
            for entry in saved.reversed() {
                lock.lock()
                let inverse = toManyInverses[Key(type: ObjectIdentifier(type(of: entry.owner)), property: entry.property)]
                lock.unlock()
                inverse?.restore(entry.owner, entry.elements)
            }
            isSuppressed = previouslySuppressed
        }

        return try body()
    }

    // MARK: - Value extraction helpers

    /// Extract an `AnyObject?` from a `didSet` value that may be wrapped in
    /// one or more layers of `Optional`/`Any`.
    private static func asObject(_ value: Any?) -> AnyObject? {
        guard let value else { return nil }
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            guard let wrapped = mirror.children.first?.value else { return nil }
            return wrapped as AnyObject
        }
        return value as AnyObject
    }

    /// Extract an `[AnyObject]` from a to-many `didSet` value.
    private static func asObjectArray(_ value: Any?) -> [AnyObject] {
        guard let value else { return [] }
        if let array = value as? [AnyObject] { return array }
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .collection else { return [] }
        return mirror.children.compactMap { child in
            let element = child.value
            return (element as AnyObject)
        }
    }
}
