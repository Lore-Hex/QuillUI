# Vendored quillcode Source

- Upstream: git@github.com:Lore-Hex/QuillCode.git
- Commit: af513673fa03476cc8cb17e2113dad75f2edb76e

QuillUI vendors this upstream app source tree so generic compatibility
lowering and Linux build tooling can run without cloning the app on every CI or
local build. Keep the app source pristine; compatibility work belongs in
QuillUI, QuillKit, QuillData, or reusable lowering and package-generation
tooling.
