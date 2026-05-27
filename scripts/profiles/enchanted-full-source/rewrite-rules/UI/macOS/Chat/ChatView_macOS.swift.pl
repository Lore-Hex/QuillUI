s/\.padding\(\)\n(\s*)\.frame\(width: 800\)/.padding(.horizontal, 40)\n$1.padding(.vertical, 16)\n$1.frame(maxWidth: .infinity)/g;
s/\.frame\(width: 800\)/.frame(maxWidth: .infinity)/g;

# Issue #17 — Enchanted parity: match macOS sidebar width 602px.
# Inject `.navigationSplitViewColumnWidth(602)` after the sidebar's
# `.toolbar { ... }` block, before the `} detail: {` closure. The Mac
# reference's sidebar is 602px; SwiftOpenUI honors this modifier on
# GTK by setting GtkPaned's initial position + min width. Matches the
# acceptance criteria in github.com/Lore-Hex/QuillUI/issues/17.
s/(\n(\s+)\}\s*\n)(\s+\} detail:)/$1$2.navigationSplitViewColumnWidth(602)\n$3/g;
