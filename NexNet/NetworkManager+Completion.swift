//
//  NetworkManager+Completion.swift
//  NexNet
//
//  Created by Aditya Chaurasia on 22/06/2026.
//

import Foundation

// MARK: - NexNetCancellable

/// An opaque handle for an in-flight network request.
///
/// Returned by every completion-handler variant of the `NetworkManager` and `NexNetClient` APIs.
/// The return value is `@discardableResult`; you only need to retain it when you intend to cancel.
///
/// ```swift
/// let token = NetworkManager.shared.fetch(responseType: User.self, url: "/me") { result in
///     // handle result
/// }
/// // Later, if the view disappears:
/// token.cancel()
/// ```
@objc public final class NexNetCancellable: NSObject {
    private let task: Task<Void, Never>

    init(_ task: Task<Void, Never>) {
        self.task = task
        super.init()
    }

    /// Requests cancellation of the associated in-flight network request.
    ///
    /// Cancellation is cooperative: the underlying `URLSession` data task is cancelled and
    /// `NexNetError.cancelled` is delivered to the completion handler.
    @objc public func cancel() {
        task.cancel()
    }
}

// MARK: - NetworkManager + Completion Handlers

extension NetworkManager {

    /// Fetches a remote resource, decodes it into `T`, and delivers the result via a completion handler.
    ///
    /// This is the completion-handler mirror of the `async throws` `fetch` method.
    /// The same URL resolution, header merging, retry policy, and logging apply.
    ///
    /// ```swift
    /// NetworkManager.shared.fetch(responseType: User.self, url: "/users/1") { result in
    ///     switch result {
    ///     case .success(let user): print(user.name)
    ///     case .failure(let error): print(error.localizedDescription)
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - responseType: The `Decodable` type to decode the response body into.
    ///   - url: Absolute URL or relative path resolved against `NexNetConfig.baseURL`.
    ///   - headers: Per-request headers merged on top of the default headers. Defaults to `nil`.
    ///   - body: Optional `Encodable` payload auto-encoded to JSON. Defaults to `nil`.
    ///   - method: HTTP verb. Defaults to `.get`.
    ///   - callbackQueue: The queue on which `completion` is called. Defaults to `.main`.
    ///   - completion: Called with `.success(T)` on success or `.failure(NexNetError)` on any error.
    /// - Returns: A `NexNetCancellable` token. Safe to discard if cancellation is not needed.
    @discardableResult
    public func fetch<T: Decodable & Sendable>(
        responseType: T.Type,
        url: String,
        headers: [String: String]? = nil,
        body: (any Encodable)? = nil,
        method: HTTPMethod = .get,
        callbackQueue: DispatchQueue = .main,
        completion: @escaping @Sendable (Result<T, NexNetError>) -> Void
    ) -> NexNetCancellable {
        NexNetCancellable(Task {
            do {
                let value = try await fetch(
                    responseType: responseType, url: url,
                    headers: headers, body: body, method: method
                )
                callbackQueue.async { completion(.success(value)) }
            } catch let error as NexNetError {
                callbackQueue.async { completion(.failure(error)) }
            } catch {
                callbackQueue.async { completion(.failure(.from(error))) }
            }
        })
    }

    /// Executes a `NetworkRequest`, decodes the body into `T`, and delivers full HTTP metadata via a completion handler.
    ///
    /// This is the completion-handler mirror of `request(_:as:decoder:)`.
    ///
    /// - Parameters:
    ///   - networkRequest: The request to execute.
    ///   - type: The `Decodable` type to decode into.
    ///   - decoder: Optional custom `JSONDecoder`. Defaults to the manager's built-in decoder.
    ///   - callbackQueue: The queue on which `completion` is called. Defaults to `.main`.
    ///   - completion: Called with `.success(NetworkResponse<T>)` or `.failure(NexNetError)`.
    /// - Returns: A `NexNetCancellable` token.
    @discardableResult
    public func request<T: Decodable & Sendable>(
        _ networkRequest: NetworkRequest,
        as type: T.Type = T.self,
        decoder: JSONDecoder? = nil,
        callbackQueue: DispatchQueue = .main,
        completion: @escaping @Sendable (Result<NetworkResponse<T>, NexNetError>) -> Void
    ) -> NexNetCancellable {
        NexNetCancellable(Task {
            do {
                let response = try await request(networkRequest, as: type, decoder: decoder)
                callbackQueue.async { completion(.success(response)) }
            } catch let error as NexNetError {
                callbackQueue.async { completion(.failure(error)) }
            } catch {
                callbackQueue.async { completion(.failure(.from(error))) }
            }
        })
    }

    /// Executes a `NetworkRequest` without decoding and delivers the raw response via a completion handler.
    ///
    /// This is the completion-handler mirror of `requestRaw(_:)`.
    ///
    /// - Parameters:
    ///   - networkRequest: The request to execute.
    ///   - callbackQueue: The queue on which `completion` is called. Defaults to `.main`.
    ///   - completion: Called with `.success(RawNetworkResponse)` or `.failure(NexNetError)`.
    /// - Returns: A `NexNetCancellable` token.
    @discardableResult
    public func requestRaw(
        _ networkRequest: NetworkRequest,
        callbackQueue: DispatchQueue = .main,
        completion: @escaping @Sendable (Result<RawNetworkResponse, NexNetError>) -> Void
    ) -> NexNetCancellable {
        NexNetCancellable(Task {
            do {
                let response = try await requestRaw(networkRequest)
                callbackQueue.async { completion(.success(response)) }
            } catch let error as NexNetError {
                callbackQueue.async { completion(.failure(error)) }
            } catch {
                callbackQueue.async { completion(.failure(.from(error))) }
            }
        })
    }
}
