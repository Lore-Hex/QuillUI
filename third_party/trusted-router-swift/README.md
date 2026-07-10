# trusted-router-swift

Swift SDK for [TrustedRouter](https://trustedrouter.com).

This is a pure Swift, zero-dependency client SDK for the Quill Cloud API gateway. It provides the same interface, error handling, SSE streaming, and GCP Confidential Space JWT verification as the Python and Javascript SDKs.

## Installation

Add this to your `Package.swift` dependencies:

```swift
.package(url: "https://github.com/jperla/trusted-router-swift.git", from: "0.4.1")
```

Then add `"TrustedRouter"` to your target's dependencies.

## Usage

```swift
import TrustedRouter

let client = try TrustedRouter(options: .init(apiKey: "your-api-key"))

// Typed catalog calls
let models = try await client.models()                    // DataList<ModelInfo>
print(models.data.map(\.id))

// Typed chat with the ChatMessage convenience constructors
let answer = try await client.chatCompletions(messages: [
    .system("Reply with one word."),
    .user("Hello?"),
])
print(answer.choices.first?.message.content ?? "")

// SSE streaming, typed chunks
let stream = try await client.chatCompletionsChunks(messages: [
    .user("Tell me a joke."),
])
for try await chunk in stream {
    if let delta = chunk.choices.first?.delta?.content {
        print(delta, terminator: "")
    }
}
```

### Fusion

Fan a request across a panel of models and let a judge model pick or synthesize
one answer. `fusion(...)` returns the same `ChatCompletion` as `chatCompletions`.
`fusionFreedomPanel` / `fusionFreedomFallbackJudges` are the recommended
most-permissive configuration.

```swift
let answer = try await client.fusion(
    messages: [.user("explain how mRNA vaccines work")],
    analysisModels: TrustedRouterConstants.fusionFreedomPanel,   // the panel
    judgeModel: "z-ai/glm-5.1",                                  // judge / synthesis model
    selectionStrategy: "first_non_refusal",                      // or synthesize / synthesize_non_refusals / first_success
    fallbackJudges: TrustedRouterConstants.fusionFreedomFallbackJudges  // tried in order if a judge refuses/fails
)
print(answer.choices.first?.message.content ?? "")
```

Or build the spec with `TrustedRouter.fusionTool(...)` and attach it to any chat
call. `preset: "quality"` or `"budget"` selects a built-in panel.

## Features

- **Asynchronous**: Built fully on modern Swift Concurrency (`async/await`, `Task`).
- **Streaming**: Native parsing of SSE using `AsyncThrowingStream`, with `URLSession.AsyncBytes` on Apple platforms and a Linux-safe byte stream fallback.
- **Attestation Verification**: Verifies the Confidential Space JWT using `CryptoKit`/`Security`.
- **Pure Swift**: No 3rd party dependencies. Operates seamlessly on macOS, iOS, tvOS, watchOS, and Linux with `FoundationNetworking`.
- **Retries**: Implements transparent exponential backoff on `429` and `5xx` errors.

## Sign in with TrustedRouter

Let users "bring their own TrustedRouter account" via the OAuth **PKCE** flow,
which mints a user-scoped key so LLM calls are billed to *that user's* credits.
On iOS/macOS, `TrustedRouterOAuth().authenticate(...)` runs the whole flow in an
`ASWebAuthenticationSession`: it generates PKCE + `state`, opens the system
browser, validates the redirect, and returns the delegated key + identity.

```swift
import TrustedRouter

let oauth = TrustedRouterOAuth(keyLabel: "My App", limit: "5")
let token = try await oauth.authenticate(
    callbackURL: "myapp://oauth-callback",          // your registered custom scheme
    presentationContextProvider: self)              // anchors the auth sheet
let key = token.key                                 // sk-tr-v1-… ; token.identity = {sub, email, …}

let who = try await fetchUserInfo(apiKey: key)      // verified identity
```

`AuthenticationServices` isn't available on Linux, so for cross-platform GUI
apps (e.g. Lore games on QuillUI) compose the pure pieces that build on every
platform: generate `PKCEChallenge.generate()` + `randomOAuthState()`, open
`oauthAuthorizeURL(callbackURL:codeChallenge:state:…)` in the system browser
(use a loopback `callback_url` like `http://localhost:3000/callback`), then call
`exchangeOAuthKey(code:codeVerifier:)` and `fetchUserInfo(apiKey:)`.

Full flow, endpoints, and security notes:
[Sign in with TrustedRouter](https://github.com/Lore-Hex/quill-router/blob/main/docs/sign-in-with-trustedrouter.md).

## License

Apache 2.0
