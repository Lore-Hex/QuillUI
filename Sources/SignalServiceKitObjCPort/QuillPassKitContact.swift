//
// PassKit contact/recurring surface -- Linux port for SignalServiceKit (Track B).
//
// Apple Pay is unavailable on QuillOS; the base PassKit shim
// (Sources/AppleFrameworkShims/PassKit/PassKit.swift) provides the inert payment
// types. Two pieces are defined HERE (in the SSK module) rather than in that shim
// because they reference Contacts types: PKContact's phoneNumber/postalAddress are
// CNPhoneNumber/CNPostalAddress, and the PassKit shim target does not depend on
// Contacts. SignalServiceKit does (it imports Contacts), so these live in the
// auto-globbed ObjCPort dir alongside the rest of the SSK port.
//
// All INERT: no PKPayment is ever produced on Linux, so PKPayment.billingContact
// is always nil and PKContact's fields are never populated. HONEST STATUS: only
// the type surface exists; Apple Pay donations are unavailable on QuillOS.
//
#if os(Linux)
import Foundation
import Contacts
import PassKit

/// Apple Pay billing/shipping contact. INERT on Linux (always produced nil via
/// PKPayment.billingContact). Mirrors the subset Stripe.parameters(for:) reads.
public final class PKContact {
    public var name: PersonNameComponents?
    public var emailAddress: String?
    public var phoneNumber: CNPhoneNumber?
    public var postalAddress: CNPostalAddress?
    public init() {}
}

public extension PKPayment {
    /// The billing contact attached to an authorized payment. INERT on Linux:
    /// no PKPayment is ever produced, so this is always nil. Computed (not stored)
    /// because PKPayment lives in the PassKit shim module and a stored property
    /// cannot be added across modules via extension.
    var billingContact: PKContact? { nil }
}

/// Apple's PKRecurringPaymentSummaryItem subclasses PKPaymentSummaryItem.
/// `intervalUnit` is a Calendar.Component (DonationUtilities sets it to `.month`);
/// `intervalCount` is the cadence multiplier. INERT type surface; inherits the
/// base `init(label:amount:)`.
public final class PKRecurringPaymentSummaryItem: PKPaymentSummaryItem {
    public var intervalUnit: Calendar.Component = .month
    public var intervalCount: Int = 1
}
#endif
