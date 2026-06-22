# NexNet

A production-grade Swift networking framework built on async/await — type-safe, zero-boilerplate, and ready to drop into any Apple platform project.

---

## Features

- **Single method API** — one `fetch` call handles GET, POST, PUT, PATCH, and DELETE
- **Dual concurrency model** — async/await and completion-handler APIs are identical in capability; use whichever fits your codebase
- **Objective-C support** — `NexNetClient` is a full `@objc NSObject` wrapper; `NexNetError` bridges to `NSError` automatically
- **Auto JSON encoding/decoding** — request bodies encoded automatically; responses decoded into any `Decodable` type
- **Snake_case → camelCase** — built-in key strategy; no custom `CodingKeys` needed
- **ISO 8601 dates** — handles both `2024-01-15T10:30:00Z` and `2024-01-15T10:30:00.123Z` out of the box
- **Typed error handling** — 20 named `NexNetError` cases covering every HTTP status code and network condition
- **Structured logging** — emoji-annotated call log with status icon, size, headers, body, response, cURL, and duration; each call bookended by a `━` separator for instant scannability
- **cURL export** — every request produces a fully copy-pasteable terminal command
- **Runtime configuration** — swap `baseURL`, headers, and timeout at any time via `configure(with:)`
- **Automatic retry** — configurable exponential back-off with per-request `RetryPolicy`
- **Cancellation** — every completion-handler call returns a `NexNetCancellable` token; call `.cancel()` to abort
- **Thread-safe** — all mutable state guarded by `NSLock`; safe to call from any `Task`
- **Zero dependencies** — built entirely on `Foundation` and `os.log`

---

## Installation

### Swift Package Manager

1. In Xcode, select **File → Add Package Dependencies…**
2. Enter the repository URL:
   ```
   https://github.com/your-username/NexNet
   ```
3. Set the version rule to **Up to Next Major** from `1.0.0`
4. Add **NexNet** to your app target

Or add it directly to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/your-username/NexNet", from: "1.0.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: ["NexNet"]
    )
]
```

---

## Quick Start

```swift
import NexNet

// 1. Configure once at app startup
NetworkManager.shared.configure(with: NexNetConfig(
    baseURL: "https://api.example.com",
    defaultHeaders: ["Authorization": "Bearer \(token)"],
    timeout: 30,
    isLoggingEnabled: true
))

// 2. Define a response model
struct User: Decodable, Sendable {
    let id: Int
    let firstName: String   // decoded from "first_name" automatically
    let email: String
}

// 3. Fetch
let user = try await NetworkManager.shared.fetch(
    responseType: User.self,
    url: "/users/1",        // relative path — baseURL prepended automatically
    headers: nil,
    body: nil,
    method: .get
)
```

---

## Configuration

Configure the shared instance once — typically in `AppDelegate.application(_:didFinishLaunchingWithOptions:)` or a SwiftUI `App.init()`:

```swift
NetworkManager.shared.configure(with: NexNetConfig(
    baseURL: "https://api.example.com",
    defaultHeaders: [
        "Authorization": "Bearer \(accessToken)",
        "X-App-Version": Bundle.main.appVersion
    ],
    timeout: 30,
    isLoggingEnabled: true
))
```

### `NexNetConfig` Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `baseURL` | `String?` | `nil` | Root URL prepended to every relative path. Absolute URLs passed to `fetch` are never modified. Both `/users/1` and `users/1` resolve correctly — the leading slash is normalised automatically. |
| `defaultHeaders` | `[String: String]` | `[:]` | Headers merged into every request on top of the framework's built-in defaults (`Accept: application/json`, `Accept-Encoding: gzip, deflate, br`). Per-request headers override these. |
| `timeout` | `TimeInterval` | `30` | Default request timeout in seconds. A per-request `timeoutInterval` always takes precedence when it differs from the 30 s default. |
| `isLoggingEnabled` | `Bool` | `true` (DEBUG) / `false` (RELEASE) | Enables or disables the structured call log. Forwarded immediately to `NetworkManager.shared.isLoggingEnabled`. |

You can also toggle logging at any time:

```swift
NetworkManager.shared.isLoggingEnabled = false
```

---

## API Reference

### `fetch` — Primary method

```swift
func fetch<T: Decodable & Sendable>(
    responseType: T.Type,
    url: String,
    headers: [String: String]?,
    body: (any Encodable)?,
    method: HTTPMethod
) async throws -> T
```

| Parameter | Description |
|-----------|-------------|
| `responseType` | The `Decodable` type the response body is decoded into. Pass `EmptyResponse.self` for endpoints that return no body (204 No Content, DELETE). |
| `url` | Absolute URL (`https://…`) or relative path (`/users/1`). A relative path is combined with `NexNetConfig.baseURL`. |
| `headers` | Optional per-request headers. Merged on top of `defaultHeaders`; per-request values win on collision. Pass `nil` to use only the defaults. |
| `body` | Any `Encodable` value. Encoded to JSON automatically and sent with `Content-Type: application/json`. Pass `nil` for requests with no body. |
| `method` | HTTP verb. One of `.get`, `.post`, `.put`, `.patch`, `.delete`, `.head`, `.options`. |

### `request` — Full metadata

When you need the HTTP status code, response headers, raw data, or call duration alongside the decoded value, use `request` instead:

```swift
let response: NetworkResponse<User> = try await NetworkManager.shared.request(
    NetworkRequest(url: url, method: .get),
    as: User.self
)

print(response.value)       // decoded User
print(response.statusCode)  // e.g. 200
print(response.duration)    // TimeInterval — total elapsed including retries
```

### `requestRaw` — Raw bytes

```swift
let raw: RawNetworkResponse = try await NetworkManager.shared.requestRaw(
    NetworkRequest(url: url, method: .get)
)
// raw.data, raw.statusCode, raw.allHeaderFields, raw.duration
```

### Completion Handlers

Every `async throws` method has a direct completion-handler mirror. All three variants return a `NexNetCancellable` token.

**`fetch` with completion** — typed decode, Result callback:

```swift
NetworkManager.shared.fetch(
    responseType: Post.self,
    url: "/posts/1"
) { result in
    // called on DispatchQueue.main by default
    switch result {
    case .success(let post): print(post.title)
    case .failure(let error): print(error.localizedDescription)
    }
}
```

**`request` with completion** — full HTTP metadata:

```swift
NetworkManager.shared.request(
    NetworkRequest(url: url, method: .get),
    as: Post.self
) { result in
    if case .success(let response) = result {
        print(response.statusCode)   // Int
        print(response.duration)     // TimeInterval
        print(response.value.title)  // decoded Post
    }
}
```

**`requestRaw` with completion** — raw bytes, no decoding:

```swift
NetworkManager.shared.requestRaw(
    NetworkRequest(url: url, method: .get)
) { result in
    if case .success(let response) = result {
        print("\(response.data.count) bytes — HTTP \(response.statusCode)")
    }
}
```

**Custom callback queue** — default is `.main`; pass any queue:

```swift
NetworkManager.shared.fetch(
    responseType: Post.self,
    url: "/posts/1",
    callbackQueue: DispatchQueue(label: "com.app.processing", qos: .utility)
) { result in
    // running on the processing queue — safe for heavy work
    // dispatch to .main before touching UI
}
```

**Cancellation:**

```swift
let token = NetworkManager.shared.fetch(responseType: Post.self, url: "/posts/1") { _ in }
// Later (e.g. viewDidDisappear):
token.cancel()   // delivers NexNetError.cancelled to the completion handler
```

---

### Retry Policy

Attach a retry policy to any `NetworkRequest`:

```swift
let req = NetworkRequest(
    url: url,
    method: .get,
    retryPolicy: RetryPolicy(
        maxAttempts: 3,
        backoffStrategy: .exponential(base: 1.0, multiplier: 2.0)
    )
)
```

| Strategy | Behaviour |
|----------|-----------|
| `.constant(interval)` | Fixed delay between every attempt |
| `.linear(base:)` | Delay grows as `base × attemptNumber` |
| `.exponential(base:multiplier:)` | Delay grows as `base × multiplierⁿ` (default) |

`RetryPolicy.default` — 3 attempts, exponential `1 s × 2.0`.
`RetryPolicy.none` — no retries (default for `fetch`).

---

## Error Handling

All errors are thrown as `NexNetError`, a `LocalizedError` enum with 20 named cases:

```swift
do {
    let post = try await NetworkManager.shared.fetch(
        responseType: Post.self, url: "/posts/1", headers: nil, body: nil, method: .get
    )
} catch let error as NexNetError {
    switch error {
    case .unauthorized:
        // refresh token and retry
    case .notFound(let url):
        print("Nothing at \(url)")
    case .decodingFailed(_, let path):
        print("Schema mismatch at key: \(path)")
    default:
        print(error.localizedDescription)
    }
}
```

### Error Case Reference

| Case | HTTP Code | When it occurs |
|------|-----------|----------------|
| `.invalidURL(String)` | — | The URL string could not be parsed, or a relative path was passed without a configured `baseURL`. |
| `.noInternetConnection` | — | Device is offline (`NSURLErrorNotConnectedToInternet`, `NetworkConnectionLost`, `DataNotAllowed`). |
| `.timeout` | — | Request exceeded the configured timeout (`NSURLErrorTimedOut`). |
| `.cancelled` | — | The enclosing `Task` was cancelled (`NSURLErrorCancelled`). |
| `.sslError(any Error)` | — | Certificate validation or TLS handshake failure. The underlying error is attached. |
| `.badRequest` | 400 | Server rejected malformed request syntax. |
| `.unauthorized` | 401 | Authentication credentials are missing or invalid. |
| `.forbidden` | 403 | Authenticated but not permitted to access the resource. |
| `.notFound(url: String)` | 404 | No resource exists at the requested URL. |
| `.unprocessableEntity` | 422 | Request was well-formed but failed server-side validation. |
| `.tooManyRequests(retryAfter: String?)` | 429 | Rate limit exceeded. `retryAfter` carries the `Retry-After` header value when present. |
| `.internalServerError` | 500 | Unexpected server-side failure. |
| `.badGateway` | 502 | Gateway received an invalid upstream response. |
| `.serviceUnavailable(retryAfter: String?)` | 503 | Server temporarily unavailable. `retryAfter` carries the `Retry-After` header value when present. |
| `.gatewayTimeout` | 504 | Upstream server did not respond within the allowed time. |
| `.httpError(statusCode: Int, data: Data?)` | any | HTTP error not individually mapped above. |
| `.emptyResponse` | — | Server returned an empty body when a decodable value was expected. Use `EmptyResponse.self` for intentionally bodyless endpoints. |
| `.decodingFailed(any Error, codingPath: String)` | — | JSON decoding failed. `codingPath` is a dot-separated key path to the offending field (e.g. `"user.address.zip"`). |
| `.encodingFailed(any Error)` | — | Serialising the request body to JSON failed. |
| `.unknown(any Error)` | — | Any error not covered by the cases above. |

Every case also provides:
- `error.localizedDescription` — human-readable sentence describing the failure
- `error.recoverySuggestion` — actionable recovery hint where applicable
- `error.isRetryable` — `true` for transient errors (timeout, 500, 502, 503, 504, 429, no connection)
- `error.statusCode` — the HTTP status code, or `nil` for non-HTTP errors

---

## Logging

NexNet logs every completed network call — including retried calls — in a structured box format. The log fires once per call after all retry attempts have settled.

### Defaults

| Build | Default | `print` | `os_log` |
|-------|---------|---------|----------|
| DEBUG | enabled | yes | no |
| RELEASE | disabled | no | yes (when enabled) |

In DEBUG builds output goes to `print` only, so each call appears exactly once in Xcode's console. In release builds `print` is compiled out and output routes to `os_log` only, making production diagnostics available through Console.app and Instruments without any source changes.

### Toggle

```swift
// Via NexNetConfig (recommended — applied at configure time)
NetworkManager.shared.configure(with: NexNetConfig(isLoggingEnabled: false))

// Direct toggle
NetworkManager.shared.isLoggingEnabled = true
```

### Log Format

Every call produces one entry bookended by `━` separators:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🌐 GET  https://api.example.com/users/1

✅ Status      200 OK
⏱️ Duration    124.3 ms
🆔 Request ID  4F3A2C1D-…
📦 Size        ↑ 0 B  ↓ 87 B

📤 Headers
{
  "Accept": "application/json",
  "Authorization": "Bearer abc123"
}

📤 Request Body
nil

📥 Response
{
  "email" : "alice@example.com",
  "first_name" : "Alice",
  "id" : 1
}

📋 cURL
curl -X GET \
'https://api.example.com/users/1' \
-H 'Accept: application/json' \
-H 'Authorization: Bearer abc123'

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

The status icon reflects the HTTP outcome — ✅ 2xx, 🔄 3xx, ⚠️ 4xx, ❌ 5xx or network error.

On failure, the **Response** field shows the error description instead of JSON:

```
📥 Response
Error — No resource was found at '/users/999' (404 Not Found).
```

---

## cURL Export

Every network call includes a fully copy-pasteable `curl` command in its log output. The generated command:

- Formatted across multiple lines with `\` continuations for readability
- Includes all request headers with single-quote-escaped values
- Includes the request body via `--data-raw` for POST/PUT/PATCH requests
- Shell-escapes single quotes in both the URL and body using the `'\''` idiom, so the command runs correctly regardless of special characters

**Example — GET with auth header:**
```sh
curl -X GET \
'https://api.example.com/users/1' \
-H 'Accept: application/json' \
-H 'Authorization: Bearer eyJhbG...'
```

**Example — POST with JSON body:**
```sh
curl -X POST \
'https://api.example.com/posts' \
-H 'Accept: application/json' \
-H 'Content-Type: application/json' \
--data-raw '{"title":"Hello","body":"World","userId":1}'
```

This is useful for:
- **Reproducing bugs** — paste the command into a terminal to confirm whether the issue is in the app or the API
- **Sharing with backend teams** — hand over the exact request that failed without any setup
- **Quick iteration** — tweak headers or bodies in the terminal before updating Swift code

---

## Objective-C

NexNet ships a first-class Objective-C API via `NexNetClient` — a plain `NSObject` subclass that wraps `NetworkManager`. No bridging headers or special setup required beyond importing the module.

```objc
@import NexNet;
// or
#import <NexNet/NexNet-Swift.h>
```

### Configuration

```objc
[[NexNetClient shared] configureWithBaseURL:@"https://api.example.com"
                            defaultHeaders:@{@"Authorization": @"Bearer token",
                                            @"X-App-Version": @"1.0.0"}
                                   timeout:30
                            loggingEnabled:YES];
```

### GET

```objc
[[NexNetClient shared] getFromURL:@"/users/1"
                          headers:nil
                       completion:^(NSData *data, NSInteger statusCode, NSError *error) {
    if (error) {
        NSLog(@"Error %ld: %@", (long)error.code, error.localizedDescription);
        return;
    }
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data
                                                        options:0 error:nil];
    NSLog(@"User: %@", json[@"name"]);
}];
```

### POST

```objc
NSError *serializeError;
NSData *body = [NSJSONSerialization dataWithJSONObject:@{@"title": @"Hello",
                                                         @"body":  @"World",
                                                         @"userId": @1}
                                               options:0
                                                 error:&serializeError];

[[NexNetClient shared] postToURL:@"/posts"
                         headers:@{@"X-Request-ID": [[NSUUID UUID] UUIDString]}
                            body:body
                      completion:^(NSData *data, NSInteger statusCode, NSError *error) {
    NSLog(@"Created — HTTP %ld", (long)statusCode);
}];
```

### PUT / PATCH / DELETE

```objc
// PUT
[[NexNetClient shared] putToURL:@"/posts/1" headers:nil body:updatedBody completion:^(...) { }];

// PATCH
[[NexNetClient shared] patchURL:@"/posts/1" headers:nil body:patchBody completion:^(...) { }];

// DELETE
[[NexNetClient shared] deleteFromURL:@"/posts/1" headers:nil
    completion:^(NSData *data, NSInteger statusCode, NSError *error) {
        NSLog(@"Deleted — HTTP %ld", (long)statusCode);
    }];
```

### Cancellation

```objc
NexNetCancellable *token = [[NexNetClient shared] getFromURL:@"/feed"
                                                     headers:nil
                                                  completion:^(...) { }];
// Cancel (e.g. viewDidDisappear):
[token cancel];
```

### NSError Bridging

`NexNetError` bridges to `NSError` automatically. Every error your completion handler receives has:

| Property | Value |
|----------|-------|
| `domain` | `com.nexnet.error` |
| `code` | HTTP status code for 4xx/5xx errors; negative code for non-HTTP errors |
| `localizedDescription` | Human-readable failure message |
| `localizedRecoverySuggestion` | Actionable hint where available |

Non-HTTP error codes:

| Error | Code |
|-------|------|
| Invalid URL | -2001 |
| No internet connection | -2002 |
| Timeout | -2003 |
| Cancelled | -2004 |
| SSL error | -2005 |
| Empty response | -2006 |
| Decoding failed | -2007 |
| Encoding failed | -2008 |

```objc
if ([error.domain isEqualToString:@"com.nexnet.error"]) {
    switch (error.code) {
        case 401:   /* refresh token */ break;
        case 404:   /* show not found UI */ break;
        case -2002: /* show offline banner */ break;
        case -2003: /* show timeout UI */ break;
    }
}
```

---

## Requirements

| Component | Minimum version |
|-----------|----------------|
| iOS | 15.0 |
| macOS | 12.0 |
| tvOS | 15.0 |
| watchOS | 8.0 |
| Swift | 5.5 |
| Xcode | 13.0 |
