//
// SignalServiceKit ObjC port for QuillOS (Track B).
//
// Three DEPRECATED "offer message" classes. Each adds no columns and declares
// no initializers (their generated SDS init section is empty), so each inherits
// its base's designated initializers -- including the grdbId SDS init the
// interaction deserializers call. They are kept only so historical YapDB / SDS
// rows still deserialize without exploding (per the upstream headers).
//
import Foundation

/// DEPRECATED. Retained for historical-row deserialization (was an "unknown
/// contact, block?" offer).
open class OWSUnknownContactBlockOfferMessage: TSErrorMessage {}

/// DEPRECATED. Retained for historical-row deserialization (was an "add to
/// profile whitelist?" offer).
open class OWSAddToProfileWhitelistOfferMessage: TSInfoMessage {}

/// DEPRECATED. Retained for historical-row deserialization (was an "add to
/// contacts?" offer).
open class OWSAddToContactsOfferMessage: TSInfoMessage {}
