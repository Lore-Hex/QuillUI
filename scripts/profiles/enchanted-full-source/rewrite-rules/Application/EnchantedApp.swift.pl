s/WindowGroup \{/WindowGroup("Quill Chat") {/g;
# Drop the secondary macOS-only `Window("Keyboard Shortcuts")` scene. The lowering
# compiles the os(macOS) blocks for the Linux port, and the generic backend renders
# this extra window's KeyboardShortcutsDemo content INLINE in the main window —
# that is the stray "Shortcuts" panel cluttering the empty-state mac-reference
# render (the sidebar's own .sheet correctly stays hidden, DBG kb=0). The sidebar
# Shortcuts button remains the in-app path.
s/Window\("Keyboard Shortcuts", id: "keyboard-shortcuts"\)\s*\{\s*KeyboardShortcutsDemo\(\)\s*\}//;
