import Testing
@testable import SwiftOpenUI

@Suite("@ObservedObject and @StateObject binding projection")
struct ObservableObjectBindingProjectionTests {
    final class Store: ObservableObject {
        var count: Int
        var title: String

        init(count: Int = 0, title: String = "") {
            self.count = count
            self.title = title
        }
    }

    struct ObservedObjectHost {
        @ObservedObject var store: Store

        init(store: Store) {
            self._store = ObservedObject(wrappedValue: store)
        }
    }

    struct StateObjectHost {
        @StateObject var store = Store(count: 3, title: "initial")
    }

    @Test("$observedObject.property returns a live two-way binding")
    func observedObjectProjectionBuildsBinding() {
        let store = Store(count: 1, title: "start")
        let host = ObservedObjectHost(store: store)

        let countBinding: Binding<Int> = host.$store.count
        #expect(countBinding.wrappedValue == 1)

        store.count = 2
        #expect(countBinding.wrappedValue == 2)

        countBinding.wrappedValue = 5
        #expect(store.count == 5)
    }

    @Test("$stateObject.property returns a live two-way binding")
    func stateObjectProjectionBuildsBinding() {
        let host = StateObjectHost()

        let countBinding: Binding<Int> = host.$store.count
        #expect(countBinding.wrappedValue == 3)

        host.store.count = 4
        #expect(countBinding.wrappedValue == 4)

        countBinding.wrappedValue = 8
        #expect(host.store.count == 8)
    }

    @Test("projected object bindings remain independent per property")
    func projectedBindingsRemainIndependent() {
        let store = Store(count: 0, title: "start")
        let host = ObservedObjectHost(store: store)

        let countBinding: Binding<Int> = host.$store.count
        let titleBinding: Binding<String> = host.$store.title

        countBinding.wrappedValue = 10
        titleBinding.wrappedValue = "done"

        #expect(store.count == 10)
        #expect(store.title == "done")
    }
}
