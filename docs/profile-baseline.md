# Linux Profile Baseline

Output from `scripts/linux-backend-profile.sh` over the Quill app
shells in CI. Two CPU samples per app: `cpu_pct_initial` (5s
window starting 5s after the first X11 window appears, i.e.
boot cost) and `cpu_pct_steady` (5s window starting 25s after,
i.e. long-term render-loop cost).

Current CI sources the app roster from
`scripts/quillui-backend-products.sh gtk-apps`, the same list used by
visual smoke coverage. The older `scripts/linux-gtk-app-products.sh`,
`scripts/linux-gtk-profile.sh`, `scripts/run-linux-gtk-profile-csv.sh`,
and `scripts/check-linux-gtk-profile-budget.sh` paths remain as
compatibility wrappers.

## Current Matrix (Linux run 25716559081, commit d69a1f4)

| App                            | build_ms | startup_ms | rss_kb  | cpu_initial | cpu_steady |
|--------------------------------|---------:|-----------:|--------:|------------:|-----------:|
| quill-enchanted                |   17,560 |          6 | 233,368 |         2.8 |        3.0 |
| quill-enchanted-upstream-slice |   13,398 |          6 | 244,940 |         6.2 |        5.8 |
| quill-icecubes                 |   13,148 |          6 | 236,156 |         3.0 |        2.8 |
| quill-netnewswire              |   13,105 |          6 | 235,852 |         5.8 |        5.6 |
| quill-codeedit                 |   11,806 |          6 | 212,468 |         2.8 |        2.6 |
| quill-signal                   |   11,666 |          5 | 230,052 |         5.6 |        5.8 |
| quill-telegram                 |   12,724 |          6 | 231,236 |         5.8 |        5.8 |
| quill-iina                     |   13,305 |          6 | 222,688 |         2.6 |        2.8 |
| quill-wireguard                |   14,901 |          6 | 215,312 |         2.6 |        2.8 |

The corrected render-projection/idempotent-load slice removed the
two sustained CPU outliers: production IceCubes dropped from
132.3/135.2 to 3.0/2.8, and production NetNewsWire dropped from
100.2/100.4 to 5.8/5.6. All user-facing app shells now idle in the
2.6-5.8% steady CPU band in CI.

### Follow-up profiler rows from the same run

| Mode                           | App               | cpu_initial | cpu_steady |
|--------------------------------|-------------------|------------:|-----------:|
| no-fetch                       | quill-icecubes    |         2.8 |        2.8 |
| no-fetch                       | quill-netnewswire |         7.0 |        5.8 |
| no-fetch + flat                | quill-icecubes    |         2.8 |        3.0 |
| no-fetch + bare                | quill-icecubes    |         3.0 |        3.4 |
| no-fetch + plain-row           | quill-icecubes    |         2.8 |        3.2 |
| no-fetch + literal-row         | quill-icecubes    |         3.2 |        3.0 |
| no-fetch + stored-props row    | quill-icecubes    |         3.0 |        2.6 |

The corrected profile branches now render real fixture rows and still
idle at fixture-app CPU levels. That confirms the high CPU was not a
fundamental `List`/`ForEach`/row-layout issue; it was repeated
equivalent state churn through render-facing model trees.

Linux CI now runs `scripts/check-linux-backend-profile-budget.sh` against
the baseline CSV with a loose 25% CPU ceiling. The threshold is meant
to catch a return to the former 100%+ render-loop spin without
flaking on normal CI variance.

The baseline and focused experiment CSVs are emitted through
`scripts/run-linux-backend-profile-csv.sh`, which keeps the CSV header,
product loop, and failure-tolerant artifact capture in one place.

## Previous Outlier Matrix (Linux run 25715271203, commit f6a27de)

| App                            | build_ms | startup_ms | rss_kb  | cpu_initial | cpu_steady |
|--------------------------------|---------:|-----------:|--------:|------------:|-----------:|
| quill-enchanted                |   16,961 |          6 | 233,248 |         3.2 |        2.6 |
| quill-enchanted-upstream-slice |   13,049 |          6 | 246,868 |         5.6 |        5.6 |
| quill-icecubes                 |   12,266 |          6 | 241,476 |   **132.3** | **135.2**  |
| quill-netnewswire              |   10,855 |          7 | 228,884 |   **100.2** | **100.4**  |
| quill-codeedit                 |   11,057 |          6 | 221,812 |         2.8 |        2.8 |
| quill-signal                   |   10,912 |          5 | 227,564 |         6.0 |        5.8 |
| quill-telegram                 |   11,581 |          7 | 220,744 |         6.0 |        6.8 |
| quill-iina                     |   12,685 |          6 | 212,224 |         2.6 |        2.6 |
| quill-wireguard                |   14,946 |          6 | 206,004 |         2.8 |        2.8 |

That run disproved the stored-render-value slice as a sufficient fix.
It also exposed an instrumentation bug: the `plain-row`,
`literal-row`, and `stored-props row` IceCubes branches rendered empty
`List`s because they bypassed `timelineContent` and never seeded
profile fixtures under `QUILLUI_DISABLE_FETCH=1`.

## Original Baseline (Linux run 25692222317, commit 530232c)

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
variable. Three experiments queued, results below.

### NavigationStack hypothesis — REJECTED (Linux run 25696415311, commit 1807e71)

`QUILLUI_PROFILE_FLAT=1` returns `timelineContent` directly
with no NavigationStack + .navigationTitle wrapper.

| Mode                       | initial | steady |
|----------------------------|--------:|-------:|
| fetch (production)         |   133.7 |  134.4 |
| no-fetch                   |    43.0 |   82.8 |
| no-fetch + flat (this run) |    36.8 |   80.2 |

Only ~5 pp drop. The busy-spin survives without the
NavigationStack wrapper. **NavigationStack is not the cause.**

### Bare-mode result — DECISIVE (Linux run 25697574646, commit 83369b4)

`QUILLUI_PROFILE_BARE=1` returns a single `Text` from `body`:
no NavigationStack, no Group, no List, no ForEach, no
`@State`-driven content rendered.

| Mode                                     | initial | steady |
|------------------------------------------|--------:|-------:|
| fetch (production)                       |   134.7 |  134.2 |
| no-fetch                                 |    45.8 |   83.4 |
| no-fetch + flat (no NavigationStack)     |    42.3 |   82.0 |
| **bare-mode** (`Text` only)              | **2.8** | **2.8** |

Bare-mode is at the **fixture-app baseline**. So:

- The GTK4 host event loop CAN idle correctly.
- The `@State` subscription bookkeeping is fine.
- The SwiftOpenUI runtime itself is not busy-spinning.

The CPU peg lives somewhere in IceCubes' specific view tree:
the `Group { … List { ForEach(statuses) { statusRow($0) } } … }`
chain.

### Historical plain-row result — superseded (Linux run 25698691689, commit f859de7)

`QUILLUI_PROFILE_PLAIN_ROW=1` keeps `List + ForEach(statuses)`
but renders each row as plain `Text(status.id)`.

| Mode                              | initial | steady |
|-----------------------------------|--------:|-------:|
| no-fetch (rich `statusRow`)       |    44.2 |   83.6 |
| **no-fetch + plain-row**          | **3.0** | **2.6** |

This looked decisive at the time, but later artifact inspection found
the profile branch was bypassing fixture seeding and rendering an
empty `List`. Treat this as historical evidence that an empty list can
idle, not as row-shape evidence. The corrected d69a1f4 run above
supersedes it.

### Historical literal-row result — superseded (Linux run 25699855677, commit 15a6417)

`QUILLUI_PROFILE_LITERAL_ROW=1` keeps the FULL statusRow
shape (HStack + Circle + nested VStack + 3 Texts + .padding)
but with literal-string Text values (no computed properties).

| Mode                                        | initial | steady |
|---------------------------------------------|--------:|-------:|
| no-fetch (rich `statusRow`)                 |    44.2 |   83.6 |
| no-fetch + plain-row (List+ForEach + Text)  |     3.0 |    2.6 |
| **no-fetch + literal-row (full layout)**    | **2.6** | **2.6** |

This result was also an empty-list baseline, not a valid full-layout
row measurement. The corrected d69a1f4 run renders literal rows,
stored-prop rows, and production rows with fixtures; all now idle at
fixture-app CPU levels. The final fix is the combination of
render-facing row/detail projections and idempotent startup state
writes, not `HTMLString.asRawText` caching alone.

### Cache-at-model attempted fix — DID NOT MOVE THE NEEDLE (commit 40c1ed4)

Promoted `HTMLString.asRawText` and `RSSItem.plainTextBody`
from computed properties to stored `let`s computed once at
init. Validated by Linux run 25700973380:

| App              | before (1ca5e81) | after cache (40c1ed4) |
|------------------|------------------|------------------------|
| quill-icecubes (fetch)    |  134.7 / 134.2 |  137.8 / 137.5 |
| quill-icecubes (no-fetch) |   43.0 /  82.8 |   43.5 /  83.0 |
| quill-netnewswire (fetch) |  120.4 / 117.8 |  119.4 / 117.0 |

Within noise — the cache didn't help. Reverted in
⟨following commit⟩ since it adds init cost without
observable benefit.

### Why the cache didn't help

Two things the bisection missed:

1. `Account.cachedDisplayName` is itself a computed property
   that constructs a fresh `HTMLString` on every read:
   ```swift
   public var cachedDisplayName: HTMLString {
       HTMLString(stringLiteral: displayName ?? username)
   }
   ```
   Caching `HTMLString.asRawText` at init means each call now
   pays the strip-+-decode cost at construction time — same
   total work, just moved.
2. `Status.content.asRawText` DID become a cheap stored read
   after the cache, but the production CPU didn't drop. That
   suggests the per-paint cost isn't dominated by
   `.asRawText`'s work — something else in the
   computed-property reading path (View-tree diff,
   String allocation in the Text init, etc.) burns the CPU.

### What the literal-row result actually demonstrated

The 80 pp drop from `statusRow` → literal-row was real, but
the *cause* isn't HTMLString's computation. The remaining
difference between cached-`statusRow` (still 137% CPU) and
literal-row (3% CPU):

- `Text(status.account.cachedDisplayName.asRawText)` reads two
  computed properties + allocates a transient `HTMLString` per
  paint.
- `Text("@\(status.account.acct)")` allocates a new
  interpolated `String` per paint.
- `Text(status.content.asRawText)` (after fix) reads a stored
  property — should be near-free.

Even with `asRawText` cached, the `cachedDisplayName`
construction + interpolation paths still allocate per paint.
And SwiftOpenUI's render loop (`g_timeout_add(5, RunLoop.main.run)`
at `Sources/Backend/GTK4/Rendering/GTK4Backend.swift:606`)
fires at 200Hz, so per-paint allocations stack.

### Next experiments queued after 25699855677

1. Replace `Text(status.account.cachedDisplayName.asRawText)`
   with `Text(status.account.username)` (stored property, no
   chain). If CPU drops → the `cachedDisplayName` HTMLString
   construction is the cost.
2. Inspect SwiftOpenUI's 200Hz RunLoop pump — possibly the
   `RunLoop.main.run(mode: .default, before: limit)` is doing
   more work than expected when `@State` updates have
   propagated. A throttle / event-driven pump might fix the
   class of problem.
3. Cache at the View level: wrap `statusRow` in a `LazyVStack`
   row or extract as a separate `View` struct so SwiftOpenUI
   can memoize.

## Method

`scripts/linux-backend-profile.sh <product> [settle] [steady]`:

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
