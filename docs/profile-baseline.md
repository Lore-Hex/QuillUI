# Linux Profile Baseline

First-run output from `scripts/linux-gtk-profile.sh` over all six
Quill app shells in CI (Linux run **25690469192**, commit
**2df694c**, `swift:6.2-noble` container, Xvfb 1180×760×24, 5s
settle then 5s CPU window).

## Numbers

| App              | build_ms | startup_ms | rss_kb  | cpu_pct_5s |
|------------------|---------:|-----------:|--------:|-----------:|
| quill-signal     |   17,652 |          6 | 219,288 |        6.8 |
| quill-telegram   |   12,024 |          5 | 221,068 |        6.8 |
| quill-iina       |   13,927 |          6 | 212,412 |        2.8 |
| quill-codeedit   |   14,096 |          5 | 214,076 |        2.8 |
| quill-icecubes   |   12,291 |          6 | 241,144 |  **132.7** |
| quill-netnewswire|   11,987 |          7 | 229,732 |   **99.4** |

`startup_ms` is launch → first X11 window appears.
`rss_kb` is `/proc/PID/status:VmRSS` after the 5s settle.
`cpu_pct_5s` is the average of 5 one-second `top -b` samples,
also taken after settle.

## What's good

- **Startup time** is uniform 5–7ms across all six apps. The
  SwiftOpenUI GTK4 backend mounts the first window quickly —
  no per-app startup tax beyond the baseline cost of the
  runtime.
- **RSS** is in a tight 207–235 MB band. About 60% of that is
  the GTK4 + GLib + Cairo + Pango stack the process maps in;
  the per-app delta is small.
- **Fixture-only apps idle near zero**: Signal/Telegram at
  6.8%, IINA/CodeEdit at 2.8%. With no network or animation
  loop the process really does sit still.

## Outliers (Phase 4 follow-up)

- **quill-icecubes 132.7%**: pegs more than one CPU during the
  sample window. It's the only app that makes a Mastodon API
  call on appear (`URLSession.shared.data(for:)` against
  mastodon.social). The fetch + JSON decode + post-decode
  re-render is in the sample window.
- **quill-netnewswire 99.4%**: same pattern — the
  Foundation-XMLParser-backed RSS reader hits
  daringfireball.net/feeds/main on appear. The 5s window
  overlaps the parse + first render.

Hypotheses to investigate:
1. The fetch path itself is fine and the spike is the
   first-frame paint of a long status / article list (heavy
   render). Check by tearing the fetch out of `onAppear` and
   re-sampling.
2. SwiftOpenUI's @MainActor diff loop fires repeatedly while
   @Published / @State updates land from the async task. Check
   by adding instrumentation around the renderer's pass count.
3. URLSession's background thread is busy-spinning waiting on
   a chunked transfer / HTTPS continuation. Check by replacing
   the real fetch with a `Data` literal.

`docs/uitest-plan.md` Phase 4 will gate against thresholds
once we have a few runs of trending data to calibrate against.
For now the numbers are uploaded to the `linux-gtk-qa`
artifact bundle as `/tmp/quillui-profile.csv` on every Linux
CI run.

## Method

`scripts/linux-gtk-profile.sh <product>`:

1. `swift build --product <product>` (build time captured
   separately so dep-cache state doesn't pollute startup).
2. `Xvfb :95 -screen 0 1180x760x24` in background.
3. Launch the app, poll `xdotool search --onlyvisible` until
   the first X11 window appears (the "rendered first frame"
   signal, not just "process exists").
4. Sleep `${QUILLUI_GTK_PROFILE_SETTLE:-5}` seconds.
5. Read `/proc/$pid/status:VmRSS` for memory.
6. `top -b -d 1 -n 6 -p $pid` for a 5-second CPU window;
   average the 5 delta samples.
7. Kill, emit one CSV row, exit.

CSV row schema:
`product,build_ms,startup_ms,rss_kb,cpu_pct_5s,exit_status`.
