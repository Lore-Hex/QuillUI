//
// SignalServiceKit TSPayment enum-string helpers for QuillOS (Track B).
//
// TSPaymentModels.h declares free functions NSStringFromTSPaymentType/State/Failure
// (defined in the excluded TSPaymentModels.m) that map the payment enums to debug
// strings for logging. TSPaymentModels.swift calls them. The enums themselves are
// ported in TSModelEnums.swift; provide the string helpers as same-module free
// functions (visible to all SSK without an import). String(describing:) yields the
// Swift case name -- meaningful for logging; exact ObjC spelling is not load-bearing.
//
import Foundation

func NSStringFromTSPaymentType(_ value: TSPaymentType) -> String {
    return String(describing: value)
}

func NSStringFromTSPaymentState(_ value: TSPaymentState) -> String {
    return String(describing: value)
}

func NSStringFromTSPaymentFailure(_ value: TSPaymentFailure) -> String {
    return String(describing: value)
}
