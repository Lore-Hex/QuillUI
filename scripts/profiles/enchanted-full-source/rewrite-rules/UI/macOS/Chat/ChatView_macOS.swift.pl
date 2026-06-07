s/\.padding\(\)\n(\s*)\.frame\((?:maxWidth|width): 800\)/.padding(.horizontal, 40)\n$1.padding(.vertical, 16)\n$1.frame(maxWidth: .infinity)/g;
s/\.frame\((?:maxWidth|width): 800\)/.frame(maxWidth: .infinity)/g;
s/Text\("Enchanted"\)/Text("Quill Chat")/g;
s/title: "Enchanted"/title: "Quill Chat"/g;

# Issue #17 — Enchanted parity: match macOS sidebar width 602px.
# Inject `.navigationSplitViewColumnWidth(602)` after the sidebar's
# `.toolbar { ... }` block, before the `} detail: {` closure. The Mac
# reference's sidebar is 602px; SwiftOpenUI honors this modifier on
# GTK by setting GtkPaned's initial position + min width. Matches the
# acceptance criteria in github.com/Lore-Hex/QuillUI/issues/17.
s/(\n(\s+)\}\s*\n)(\s+\} detail:)/$1$2.navigationSplitViewColumnWidth(602)\n$3/g;

# Issue #25 — Enchanted parity: match macOS alert dialog width 1524px.
# Constrain the UnreachableAPIView call in the detail pane to 1524pt
# max width. The Mac reference's offline alert is 1524pt wide; the
# upstream layout lets the alert fill the detail pane (~1594pt after
# inner paddings) so without this cap the Linux output overshoots.
# Negative-lookahead guards against double-applying if a future rule
# adds .frame(...) too.
s/UnreachableAPIView\(\)(?!\.frame)/UnreachableAPIView().frame(maxWidth: 1524)/g;
