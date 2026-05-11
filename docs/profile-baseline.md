# Linux Profile Baseline

Output from `scripts/linux-gtk-profile.sh` over all six Quill app
shells in CI. Two CPU samples per app: `cpu_pct_initial` (5s
window starting 5s after the first X11 window appears, i.e.
boot cost) and `cpu_pct_steady` (5s window starting 25s after,
i.e. long-term render-loop cost).

## Numbers (Linux run 25692222317, commit 530232c)

| App              | build_ms | startup_ms | rss_kb  | cpu_initial | cpu_steady |
|------------------|---------:|-----------:|--------:|------------:|-----------:|
| quill-signal     |   15,742 |          6 | 219,520 |         5.8 |        6.0 |
| quill-telegram   |   11,914 |          6 | 221,052 |         6.0 |        6.2 |
| quill-iina       |   10,875 |          5 | 212,420 |         2.8 |        2.8 |
| quill-codeedit   |   11,874 |          6 | 212,900 |         2.6 |        2.6 |
| quill-icecubes   |   13,066 |          5 | 231,324 |   **129.3** | **131.5**  |
| quill-netnewswire|   11,600 |          5 | 229,560 |    **98.8** | **100.2**  |

`startup_ms` is launch → first X11 window appears.
`rss_kb` is `/proc/PID/status:VmRSS` after the 5s settle.
CPU columns are averages of 5 one-second `top -b` samples.

## What's good

- **Startup time** is uniform 5–6ms across all six apps. The
  SwiftOpenUI GTK4 backend mounts the first window quickly —
  no per-app startup tax beyond the baseline cost of the
  runtime.
- **RSS** is in a tight 207–235 MB band. About 60% of that is
  the GTK4 + GLib + Cairo + Pango stack the process maps in;
  the per-app delta is small.
- **Fixture-only apps idle near zero in both windows**:
  Signal/Telegram at 5.8–6.2%, IINA/CodeEdit at 2.6–2.8%. The
  delta between initial and steady is within ±0.2%, so the
  GTK4 render loop correctly idles when nothing's happening.

## Outliers — sustained, not fetch-bound

- **quill-icecubes**: 129.3% initial → 131.5% steady (Δ +2.2)
- **quill-netnewswire**: 98.8% initial → 100.2% steady (Δ +1.4)

Both pegs hold at 25s after the first window appears — well
past any reasonable fetch + decode budget for the Mastodon
public timeline / daringfireball.net RSS feed. The CPU
continues to burn while the app sits there with nothing
visibly happening.

Distinguishing characteristics:

- Only apps using `URLSession.shared.data(for:)` on appear.
- Only apps with `@StateObject` (NetNewsWire) or `@State`
  collections that grow from empty to populated (IceCubes).
- Both pass the GTK visual smoke (window renders, content is
  visible) — this is a CPU smell, not a render-failure smell.

The fixture-only apps prove the GTK4 baseline can idle
cleanly. So the spike is in one of these layers, in order of
likelihood:

1. SwiftOpenUI's diff loop is firing on @Published / @State
   updates that don't actually change rendered output.
   `RSSReaderModel.fetch()` writes `isLoading` twice + items
   + selectedID + error — each write hits a Published
   notification.
2. URLSession on swift-corelibs-foundation (Linux Swift)
   keeps a poll loop alive even after the response data is
   received. macOS Foundation's URLSession sleeps cleanly.
3. The first-render-after-list-populates pass is expensive
   and gets retried in a loop because of some animation +
   layout invalidation interaction.

Next investigation slice: tear `onAppear`'s `fetchTimeline()`
out of IceCubes (or replace with a hardcoded fixture) and
re-run profiling. If CPU drops to ~3% in both windows, the
spike is in the fetch / decode / publish path. If CPU stays
pegged, it's in the rendered-list / SwiftOpenUI-diff path.
Either way the answer narrows the search.

## Method

`scripts/linux-gtk-profile.sh <product> [settle] [steady]`:

1. `swift build --product <product>` (build time captured
   separately so dep-cache state doesn't pollute startup).
2. `Xvfb :95 -screen 0 1180x760x24` in background.
3. Launch the app, poll `xdotool search --onlyvisible` until
   the first X11 window appears (the "rendered first frame"
   signal, not just "process exists").
4. Sleep `<settle>` seconds (default 5). Read `VmRSS`.
5. `top -b -d 1 -n 6 -p $pid` for a 5-second CPU window;
   average the 5 delta samples → `cpu_pct_initial`.
6. Sleep `<steady>` seconds (default 20). Re-sample CPU →
   `cpu_pct_steady`.
7. Kill, emit one CSV row, exit.

CSV row schema:
`product,build_ms,startup_ms,rss_kb,cpu_pct_initial,cpu_pct_steady,exit_status`.
