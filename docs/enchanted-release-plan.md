# Enchanted Release Plan

Enchanted / Quill Chat is the first polished QuillUI app. The goal is an
installable Linux desktop app built from the real upstream source through
QuillUI compatibility layers, with behavior and presentation close enough that
Apple Swift developers trust the approach.

This is the release focus. Other app targets remain valuable conformance tests,
but they should not pull core work away from Enchanted unless they expose a
reusable QuillUI gap that also improves Enchanted.

## Product Statement

> QuillUI brings Apple Swift app source to Linux with source-level compatibility
> and macOS-quality rendering.

For Enchanted, that means:

- Real upstream Enchanted / Quill Chat source is the app input.
- Linux compatibility comes from QuillUI, QuillData, QuillKit, source lowering,
  and backend renderers.
- The upstream app source is not edited to make Linux work.
- Platform-specific Linux services are explicit adapters, not hidden stubs.

## Release Gates

### Source

- Real upstream source is fetched by `scripts/fetch-upstream.sh`.
- The generated `quill-chat-linux` app builds from lowered source copies.
- The profile has a small, auditable budget and contains only app source-shape
  rules.
- No hand-written Enchanted reimplementation target is treated as the release
  artifact.
- App-specific fallback behavior lives in Quill libraries when reusable.

### Build

- macOS test suite passes.
- Linux Swift tests pass on the supported GTK build graph.
- Generated Enchanted full-source compile passes.
- GTK visual and interaction smokes pass.
- Qt rows stay compile/smoke checked as abstraction pressure, but GTK is the
  release backend.

### Visual

- Empty conversation screen matches the captured Mac reference landmarks:
  sidebar, header, wordmark, four prompt cards, alert when seeded, and composer.
- Selected transcript screen shows leading assistant messages and trailing user
  bubbles with correct alignment.
- Markdown transcript coverage includes paragraphs, inline formatting, links,
  quotes, code blocks, lists, and tables as practical app-facing behavior.
- Settings and Completions sheets render at stable sizes and positions.
- QuillPaint-backed controls replace GTK CSS approximations where native widget
  geometry blocks parity.

### Interaction

Required click-through flows:

- Launch with seeded data.
- Select an existing conversation.
- Select a model.
- Start a chat from a prompt card.
- Type in the composer without losing focus.
- Send from the composer.
- Persist and reload the conversation.
- Open Settings from the sidebar and from the unreachable-state banner.
- Edit the endpoint / bearer-token fields.
- Open Completions.
- Copy chat output.
- New chat.
- Clear all conversations with confirmation.
- Exercise unreachable-state UI.

### Data And Services

- Conversation persistence uses QuillData through the app-facing SwiftData
  contract.
- Ollama model listing, reachability, and streaming chat use real HTTP behavior.
- Secrets and tokens use the best available Linux storage adapter once the
  release crosses from demo to installable app.
- Updater, USB, speech, panels, and other unsupported Apple services either have
  native Linux adapters or clear user-facing fallback behavior.

### Packaging

- Provide a local run script for developers.
- Provide a reproducible release build path.
- Prefer Flatpak for the first public installable artifact.
- Capture screenshots from the release artifact, not a special test-only binary.
- Document required local services, especially Ollama endpoint configuration.

## Current Priority Order

1. Finish the remaining toolbar and chat-state mutation flows, starting with
   New Chat from a selected transcript.
2. Move remaining profile-only behavior into reusable QuillUI/QuillKit APIs.
3. Wire QuillPaint into the controls that currently fail visual parity.
4. Produce a release artifact and rerun visual/interaction smoke against it.
5. Only then resume NetNewsWire as the next public app.

Recently cleared:

- Typed composer focus/input is covered by the real-source GTK mac-reference
  interaction verifier.
- Composer-send UI transition is covered by the real-source GTK mac-reference
  interaction verifier: typed text submits with Return and becomes a trailing
  user message while the unreachable banner and composer remain stable.
- Live composer-send behavior is covered by `scripts/quill-chat-functional-check.sh`:
  the real composer submits exactly one typed user prompt to mock Ollama, renders
  the streamed assistant reply, and persists user plus assistant rows through
  QuillData.
- Relaunch persistence is covered by the same functional harness when
  `QUILLUI_FUNCTIONAL_VERIFY_RELAUNCH=1`: after the live send it restarts the
  app with the same `QUILLDATA_HOME`, selects the persisted conversation from
  the sidebar, verifies no second `/api/chat` request was made, and checks the
  relaunched transcript screenshot.
- Settings and Completions sheet presentation are covered by the real-source GTK
  mac-reference interaction verifier.
- Settings endpoint editing is covered by the same verifier via the
  `settings-endpoint-typed` row.
- Settings bearer-token editing is covered by the same verifier via the
  `settings-bearer-token-typed` row.
- Settings ping-interval editing is covered by the same verifier via the
  `settings-ping-interval-typed` row.
- Settings default-model picker selection is covered by the same verifier via
  the `settings-default-model-selected` row.
- Settings delete-all confirmation is covered by the same verifier via the
  `settings-delete-confirmation` row.
- Completions sheet presentation, nested New Completion editing, saving a
  renamed completion back into the list, editing an existing completion, and
  deleting a completion are covered by the same verifier via the
  `completions-panel`, `completions-new-sheet`, `completions-save`,
  `completions-edit-save`, and `completions-delete` rows.
- New Chat toolbar reset is covered by the same verifier via the `new-chat`
  row: it selects a seeded transcript first, clicks the compose action, and
  verifies the empty chat wordmark, prompt cards, unreachable alert, and
  composer return.

## Non-Goals For The First Release

- Full SwiftUI API parity.
- Full AppKit/UIKit replacement.
- Real Apple service replication on Linux.
- Multi-app polish across the whole matrix.
- Binary compatibility with Apple apps.

The first release should prove one thing cleanly: a real Apple Swift app can be
rebuilt for Linux through QuillUI and feel like a serious desktop app.
