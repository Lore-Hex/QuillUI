// NetNewsWireMacShared (umbrella)
// ===============================
// Re-exports every NetNewsWire upstream piece we direct-compile so
// QuillNetNewsWireCore (and other consumers) can `import NetNewsWireMacShared`
// once and get the full bundle:
//   - RefreshInterval + ArticleTextSize → NetNewsWireSmallTypes
//   - Mac AppDefaults                   → NetNewsWireMacAppDefaults
//   - Article Theme bundle pipeline     → NetNewsWireArticleStyles
//   - Article Extractor / ExtractedArticle → NetNewsWireArticleExtractor
//
// Article Rendering (the WebKit-rendering pipeline) is a follow-up — it
// pulls in NetNewsWire's Shared/Extensions and Shared/Activity, which
// transitively brings most of Shared/.

@_exported import NetNewsWireSmallTypes
@_exported import NetNewsWireMacAppDefaults
@_exported import NetNewsWireArticleStyles
@_exported import NetNewsWireArticleExtractor
