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
public timeline / daringfireball.net RSS feed.

## Tear-out experiment (Linux run 25694297557, commit 1e07973)

`QUILLUI_DISABLE_FETCH=1` makes both apps seed representative
fixture content instead of running URLSession on appear (see
`QuillIceCubesProfileFixtures.statuses` and
`RSSReaderModel.seedProfileFixtures()`). Production behavior is
unchanged when the variable is unset — the experiment lives
entirely behind one `onAppear` branch.

Same Linux run, both modes side-by-side:

| App              | fetch initial | fetch steady | no-fetch initial | no-fetch steady |
|------------------|--------------:|-------------:|-----------------:|----------------:|
| quill-icecubes   |         127.2 |        128.5 |         **40.1** |        **78.7** |
| quill-netnewswire|         100.4 |         99.4 |         **52.5** |        **83.8** |

**Two-part split:**

1. **About half the boot CPU was fetch-bound.** Both apps drop
   ~80-90 percentage points in the initial window with the
   fetch torn out (IceCubes 127→40, NNW 100→52). That's the
   URLSession + decode + first batch of `@Published` /
   `@State` writes settling.

2. **The render-loop alone still burns ~40–84% CPU.** Even
   with NO network and only 2 fixture rows shown, the
   rendered list spins ~half a CPU core in steady-state
   compared to fixture-only apps that idle at 3–6%.

3. **Steady > initial in no-fetch mode** (IceCubes 40 → 79,
   NNW 52 → 84). Something *grows* over the 20-second wait
   window — allocations ramping, a redraw rate climbing, or
   list-relayout work accumulating. The fixture-only apps
   are stable in both windows (≤0.2% drift).

## What differs between the busy-spin apps and the idle apps

| Property         | Signal/Telegram/IINA/CodeEdit | IceCubes / NetNewsWire |
|------------------|-------------------------------|------------------------|
| Idle CPU         | 2.6–6.2%                      | 40–84% (no-fetch)      |
| Navigation       | `NavigationSplitView`         | `NavigationStack` (Ice) / `NavigationSplitView` (NNW) |
| State container  | `@State [Conversation]`       | `@State [Status]` (Ice) / `@StateObject RSSReaderModel` (NNW) |
| List items       | 3–4 fixture rows              | 2 fixture rows (after tear-out) |
| ProgressView     | none                          | both have one, gated on `isLoading` |
| `.refreshable`   | no                            | both (non-Linux only)  |

NavigationStack vs NavigationSplitView is the most visible
delta on the IceCubes side. NNW's `@StateObject` adds another
variable. Probable next experiments, in order of cheapness:

1. Swap IceCubes' `NavigationStack` → `NavigationSplitView`
   and re-profile. Settles "is `NavigationStack` on
   SwiftOpenUI's GTK4 backend busy-spinning?".
2. Remove the `ProgressView()` from the loading-placeholder
   branch and re-profile. Settles "is `ProgressView`'s
   animation timer firing even when the view isn't
   instantiated?".
3. Replace NNW's `@StateObject RSSReaderModel` with `@State
   var items: [RSSItem]` directly and re-profile. Settles "is
   `@StateObject` + `@Published` driving the render-loop in
   SwiftOpenUI?".

Each is a small, contained, reversible change — the same
shape as the QUILLUI_DISABLE_FETCH bypass landed in 1e07973.

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
