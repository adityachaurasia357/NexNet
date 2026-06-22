//
//  ExampleUsage.swift
//  NexNet
//
//  Illustrates the most common NexNet usage patterns.
//  All symbols are private so this file can live in the framework
//  target without polluting the public API surface.
//

import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// MARK: 1 — Global Configuration
//
// Call once at app startup — AppDelegate.application(_:didFinishLaunchingWith:)
// or SwiftUI App.init().
// ─────────────────────────────────────────────────────────────────────────────

private func setupNexNet() {
    NetworkManager.shared.configure(with: NexNetConfig(
        baseURL: "https://jsonplaceholder.typicode.com",  // relative paths resolve against this
        defaultHeaders: [
            "Authorization": "Bearer my-secret-token",
            "X-App-Version": "1.0.0"
        ],
        timeout: 30,           // seconds; per-request timeouts override this
        isLoggingEnabled: true // default: true in DEBUG, false in RELEASE
    ))
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: 2 — Response Models
//
// Declare plain Decodable structs.
// Snake_case keys (e.g. "user_id") are auto-converted to camelCase (userId)
// by the built-in JSONDecoder (.convertFromSnakeCase).
// ─────────────────────────────────────────────────────────────────────────────

private struct Post: Decodable, Sendable {
    let id: Int
    let userId: Int      // decoded from JSON key "userId" or "user_id"
    let title: String
    let body: String
}

private struct CreatePostRequest: Encodable, Sendable {
    let title: String
    let body: String
    let userId: Int
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: 3 — GET Request
//
// Relative paths are automatically combined with the configured baseURL.
//   "/posts/1"  →  "https://jsonplaceholder.typicode.com/posts/1"
// ─────────────────────────────────────────────────────────────────────────────

private func fetchPost(id: Int) async throws -> Post {
    try await NetworkManager.shared.fetch(
        responseType: Post.self,
        url: "/posts/\(id)",   // relative path — baseURL prepended automatically
        headers: nil,          // uses defaultHeaders from NexNetConfig
        body: nil,
        method: .get
    )
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: 4 — POST Request with Encodable body
//
// Any Encodable value is accepted as `body` and automatically encoded to JSON.
// The "Content-Type: application/json" header is added for you.
// Per-request headers are merged on top of the global defaultHeaders.
// ─────────────────────────────────────────────────────────────────────────────

private func createPost(title: String, body: String) async throws -> Post {
    let payload = CreatePostRequest(title: title, body: body, userId: 1)

    return try await NetworkManager.shared.fetch(
        responseType: Post.self,
        url: "/posts",
        headers: ["X-Request-ID": UUID().uuidString],  // per-request header
        body: payload,                                   // auto-encoded to JSON
        method: .post
    )
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: 5 — DELETE (no response body)
//
// Use EmptyResponse as responseType for endpoints that return 204 No Content
// or any other response with an empty body.
// ─────────────────────────────────────────────────────────────────────────────

private func deletePost(id: Int) async throws {
    _ = try await NetworkManager.shared.fetch(
        responseType: EmptyResponse.self,
        url: "/posts/\(id)",
        headers: nil,
        body: nil,
        method: .delete
    )
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: 6 — Full Error Handling
//
// Every NexNetError case is handled individually so the caller can react
// with precision — show a specific alert, refresh a token, schedule a retry,
// or log silently depending on the error type.
// ─────────────────────────────────────────────────────────────────────────────

private func loadPost(id: Int) async {
    do {
        let post = try await fetchPost(id: id)
        print("Loaded: \(post.title)")

    } catch let error as NexNetError {
        switch error {

        // ── URL ──────────────────────────────────────────────────────────────
        case .invalidURL(let url):
            // The URL string could not be parsed. Check for typos or
            // missing baseURL when using relative paths.
            print("[NexNet] Invalid URL '\(url)' — verify the path and baseURL configuration.")

        // ── Network conditions ────────────────────────────────────────────────
        case .noInternetConnection:
            // Device is offline. Prompt the user to check connectivity.
            print("[NexNet] No internet connection — ask user to check Wi-Fi or mobile data.")

        case .timeout:
            // Server took too long. Consider increasing NexNetConfig.timeout
            // or retrying with RetryPolicy.default.
            print("[NexNet] Request timed out — consider increasing the timeout or retrying.")

        case .cancelled:
            // The owning Task was cancelled (e.g. view disappeared).
            // Usually safe to ignore; no user-visible error needed.
            print("[NexNet] Request cancelled.")

        case .sslError(let underlying):
            // Certificate validation failed. Never silently bypass SSL errors.
            print("[NexNet] SSL/TLS error — \(underlying.localizedDescription)")

        // ── Client errors (4xx) ───────────────────────────────────────────────
        case .badRequest:
            // 400: Malformed request. Likely a bug in the request construction.
            print("[NexNet] 400 Bad Request — check request parameters and body.")

        case .unauthorized:
            // 401: Token is missing or expired. Refresh and retry.
            print("[NexNet] 401 Unauthorized — refresh the access token and retry.")

        case .forbidden:
            // 403: Authenticated but lacks permission for this resource.
            print("[NexNet] 403 Forbidden — the current user cannot access this resource.")

        case .notFound(let url):
            // 404: Resource does not exist at the given URL.
            print("[NexNet] 404 Not Found — no resource at '\(url)'.")

        case .unprocessableEntity:
            // 422: Request was well-formed but failed server-side validation.
            // Show validation feedback to the user.
            print("[NexNet] 422 Unprocessable Entity — check the submitted data for validation errors.")

        case .tooManyRequests(let retryAfter):
            // 429: Rate-limited. Honour the Retry-After header when present.
            if let retryAfter {
                print("[NexNet] 429 Too Many Requests — retry after \(retryAfter) second(s).")
            } else {
                print("[NexNet] 429 Too Many Requests — back off before retrying.")
            }

        // ── Server errors (5xx) ───────────────────────────────────────────────
        case .internalServerError:
            // 500: Unrecoverable server error. Retry later or show a generic error.
            print("[NexNet] 500 Internal Server Error — try again in a moment.")

        case .badGateway:
            // 502: Gateway received an invalid upstream response (transient).
            print("[NexNet] 502 Bad Gateway — upstream issue; retry shortly.")

        case .serviceUnavailable(let retryAfter):
            // 503: Service is temporarily down (maintenance, overload).
            if let retryAfter {
                print("[NexNet] 503 Service Unavailable — retry after \(retryAfter) second(s).")
            } else {
                print("[NexNet] 503 Service Unavailable — try again later.")
            }

        case .gatewayTimeout:
            // 504: Upstream server too slow to respond. Retry with back-off.
            print("[NexNet] 504 Gateway Timeout — upstream server did not respond in time.")

        // ── Other HTTP ────────────────────────────────────────────────────────
        case .httpError(let statusCode, _):
            // Any HTTP status not individually mapped above.
            print("[NexNet] HTTP \(statusCode) — unhandled status code.")

        // ── Body / Decoding ───────────────────────────────────────────────────
        case .emptyResponse:
            // Server returned no body when one was expected.
            // Use EmptyResponse.self as responseType for endpoints that intentionally
            // return no content (204 / DELETE).
            print("[NexNet] Empty response — server returned no body.")

        case .decodingFailed(let underlying, let codingPath):
            // JSON decoding failed. codingPath pinpoints the offending key.
            if codingPath.isEmpty {
                print("[NexNet] Decoding failed — \(underlying.localizedDescription)")
            } else {
                print("[NexNet] Decoding failed at '\(codingPath)' — \(underlying.localizedDescription)")
            }

        case .encodingFailed(let underlying):
            // Encoding the request body to JSON failed.
            print("[NexNet] Body encoding failed — \(underlying.localizedDescription)")

        // ── Catch-all ─────────────────────────────────────────────────────────
        case .unknown(let underlying):
            // An error not covered by the typed cases above.
            print("[NexNet] Unexpected error — \(underlying.localizedDescription)")

        @unknown default:
            // Guards against future NexNetError cases added in later versions.
            print("[NexNet] Unrecognised error — \(error.localizedDescription)")
        }

    } catch {
        // Non-NexNetError: shouldn't occur under normal operation.
        print("Unexpected non-NexNet error: \(error)")
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: 7 — Completion Handler API (Swift)
//
// Every async/await method has a direct completion-handler mirror.
// All callbacks fire on DispatchQueue.main by default; pass callbackQueue:
// to route to a background queue instead.
//
// The returned NexNetCancellable token lets you abort the request at any time
// (e.g. when a view disappears). Discard the return value if you don't need
// cancellation.
// ─────────────────────────────────────────────────────────────────────────────

// 7a — GET with Result<T, NexNetError> callback
private func fetchPostCallback(id: Int) {
    NetworkManager.shared.fetch(
        responseType: Post.self,
        url: "/posts/\(id)"
    ) { result in
        // Called on DispatchQueue.main
        switch result {
        case .success(let post):
            print("Loaded via callback: \(post.title)")
        case .failure(let error):
            print("Error: \(error.localizedDescription)")
        }
    }
}

// 7b — POST with callback, capturing the cancellation token
private var pendingRequest: NexNetCancellable?

private func createPostCallback(title: String, body: String) {
    let payload = CreatePostRequest(title: title, body: body, userId: 1)

    pendingRequest = NetworkManager.shared.fetch(
        responseType: Post.self,
        url: "/posts",
        headers: ["X-Request-ID": UUID().uuidString],
        body: payload,
        method: .post
    ) { result in
        switch result {
        case .success(let post): print("Created: \(post.id)")
        case .failure(let error): print("Create failed: \(error.localizedDescription)")
        }
    }
}

// 7c — Cancel an in-flight request (e.g. view disappeared)
private func cancelPendingRequest() {
    pendingRequest?.cancel()
    pendingRequest = nil
}

// 7d — Full HTTP metadata via callback (status code, headers, duration)
private func fetchPostWithMetadata(id: Int) {
    guard let url = URL(string: "https://jsonplaceholder.typicode.com/posts/\(id)") else { return }

    NetworkManager.shared.request(
        NetworkRequest(url: url, method: .get),
        as: Post.self
    ) { result in
        switch result {
        case .success(let response):
            print("Status: \(response.statusCode)")
            print("Duration: \(String(format: "%.1fms", response.duration * 1000))")
            print("Title: \(response.value.title)")
        case .failure(let error):
            print("Request failed: \(error.localizedDescription)")
        }
    }
}

// 7e — Raw bytes callback (useful for image downloads, binary data, custom decoding)
private func downloadRawData(from urlString: String) {
    guard let url = URL(string: urlString) else { return }

    NetworkManager.shared.requestRaw(
        NetworkRequest(url: url, method: .get)
    ) { result in
        switch result {
        case .success(let response):
            print("Received \(response.data.count) bytes — HTTP \(response.statusCode)")
        case .failure(let error):
            print("Download failed: \(error.localizedDescription)")
        }
    }
}

// 7f — Custom callback queue (useful for background processing)
private func fetchPostOnBackground(id: Int) {
    let processingQueue = DispatchQueue(label: "com.example.processing", qos: .utility)

    NetworkManager.shared.fetch(
        responseType: Post.self,
        url: "/posts/\(id)",
        callbackQueue: processingQueue   // callback fires on background queue
    ) { result in
        // Running on processingQueue — safe to do heavy work here.
        // Dispatch to main manually before touching UI.
        if case .success(let post) = result {
            DispatchQueue.main.async { print("UI update: \(post.title)") }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: 8 — NexNetClient (Objective-C Bridge)
//
// NexNetClient is a plain NSObject subclass exposing every HTTP verb as an
// @objc method. It is callable from both Swift and Objective-C.
//
// In an Objective-C file:
//   @import NexNet;
//   [[NexNetClient shared] configureWithBaseURL:@"https://api.example.com" ...]
//
// NexNetError bridges automatically to NSError with domain "com.nexnet.error"
// and a meaningful error code — HTTP errors use their status code,
// non-HTTP errors use negative codes in the -2000 range.
// ─────────────────────────────────────────────────────────────────────────────

// 8a — Configure via the ObjC-compatible client
private func setupNexNetClient() {
    NexNetClient.shared.configure(
        baseURL: "https://jsonplaceholder.typicode.com",
        defaultHeaders: ["Authorization": "Bearer my-secret-token"],
        timeout: 30,
        loggingEnabled: true
    )
}

// 8b — GET via NexNetClient (identical call from ObjC: [[NexNetClient shared] get:...])
private func fetchPostObjC(id: Int) {
    NexNetClient.shared.get(
        url: "/posts/\(id)",
        headers: nil
    ) { data, statusCode, error in
        // data: raw JSON bytes — parse with JSONSerialization or JSONDecoder
        // statusCode: HTTP status code (e.g. 200, 404)
        // error: NSError with domain "com.nexnet.error", or nil on success
        if let error {
            print("Error \(error.code): \(error.localizedDescription)")
            return
        }
        guard let data else { return }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            print("ObjC GET response: \(json["title"] ?? "no title")")
        }
    }
}

// 8c — POST via NexNetClient (pre-encode the body with JSONSerialization)
private func createPostObjC(title: String, body: String) {
    let payload: [String: Any] = ["title": title, "body": body, "userId": 1]
    let bodyData = try? JSONSerialization.data(withJSONObject: payload)

    NexNetClient.shared.post(
        url: "/posts",
        headers: ["X-Request-ID": UUID().uuidString],
        body: bodyData
    ) { data, statusCode, error in
        if let error {
            print("POST failed (\(error.code)): \(error.localizedDescription)")
            return
        }
        print("POST succeeded — HTTP \(statusCode), \(data?.count ?? 0) bytes")
    }
}

// 8d — DELETE via NexNetClient
private func deletePostObjC(id: Int) {
    NexNetClient.shared.delete(
        url: "/posts/\(id)",
        headers: nil
    ) { _, statusCode, error in
        if let error {
            print("DELETE failed: \(error.localizedDescription)")
        } else {
            print("DELETE succeeded — HTTP \(statusCode)")
        }
    }
}

// 8e — Cancellation via NexNetClient (same NexNetCancellable token)
private var objcRequest: NexNetCancellable?

private func startAndCancelObjCRequest() {
    objcRequest = NexNetClient.shared.get(url: "/posts", headers: nil) { _, _, _ in }
    // Cancel immediately (e.g. if the initiating view was dismissed)
    objcRequest?.cancel()
}
