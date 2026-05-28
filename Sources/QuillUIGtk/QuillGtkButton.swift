#if os(Linux)
// NOTE: The full QuillPaint GTK button chrome hook — drawing `MacButtonPaint` into a
// `GtkDrawingArea` overlay and reflecting live `GtkStateFlags` (pressed/focused/hovered)
// — is deferred to a dedicated, Linux-verified follow-up.
//
// The previous implementation here could not compile against the GTK4 FFI surface:
//   * `GtkStateFlags` is imported as a plain RawRepresentable (no `OptionSet.contains`),
//   * `gboolean` (Int32) cannot be used directly as a `Bool`,
//   * `GtkOverlay` is opaque (no Swift struct to `assumingMemoryBound(to:)`),
//   * the `GtkCssProvider` handle needs a `gpointer` cast for `g_object_unref`.
//
// Those idioms have no existing precedent elsewhere in QuillUIGtk and cannot be verified
// without a GTK4 Linux toolchain, so the hook is stubbed to a no-op until it can be
// implemented and verified on Linux. The macOS `.quillPaint(...)` chrome (the parity goal)
// is unaffected. Tracking issue filed for the real implementation.
public func installQuillButtonHook() {}
#endif
