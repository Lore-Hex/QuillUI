<!-- BEGIN LOOM ORCHESTRATION -->
This repository uses [Loom](https://github.com/rjwalters/loom) for AI-powered development orchestration. See `.loom/CLAUDE.md` for the full guide (roles, labels, worktrees, configuration).
<!-- END LOOM ORCHESTRATION -->

## Porting macOS apps & libraries to Linux — read first

Before bringing real Apple/upstream code to Linux, read **[docs/porting-lessons.md](docs/porting-lessons.md)**.

Core principle: **clone the missing macOS API into the lib (so verbatim Apple source compiles) — don't work around it in the app.** Each gap you hit is a unit of work for the macOS-lib clone. The doc also covers: the faithful-reimpl-UI + verbatim-vendored-frameworks model; the vendoring pattern (name the target to match the real `import`); a running catalog of macOS-vs-Linux gaps that only Linux CI catches (`NSString.localizedStringWithFormat`, `DateComponents`/`Calendar` SwiftOpenUI shadowing, `Text(styledRuns:)`/`Text.Run`, …); CI topology (verify the **full** macOS + Linux rollup, not one job); `swift test` harness quirks (hide `.upstream/wireguard-apple`; commit Package.swift before validating); and branch-first / one-small-PR discipline.