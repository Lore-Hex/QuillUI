import Foundation

#if os(Linux)
@attached(member, names: named(access), named(withMutation))
@attached(memberAttribute)
@attached(conformance)
public macro Observable() = #externalMacro(module: "QuillDataMacros", type: "QuillObservableMacro")
#endif
