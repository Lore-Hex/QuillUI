# QuillUI Vendored Source

This directory vendors the SolderScope upstream source used by QuillUI's
Linux compatibility CI.

- Upstream: https://github.com/rjwalters/SolderScope
- Revision: 54693b618ca11e86b005474246664fe1f5473449
- License: MIT, preserved in `LICENSE`

The vendored tree lets `scripts/fetch-upstream.sh solderscope` materialize a
local `.upstream/solderscope` checkout without network access. Set
`QUILLUI_REFRESH_VENDORED_SOURCE=1` to bypass this copy and fetch upstream.
