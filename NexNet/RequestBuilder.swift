//
//  RequestBuilder.swift
//  NexNet
//

import Foundation

public protocol RequestBuilderProtocol: Sendable {
    func build(from request: NetworkRequest) throws -> URLRequest
}

/// Converts a `NetworkRequest` model into a concrete `URLRequest`.
public struct RequestBuilder: RequestBuilderProtocol {
    public let defaultHeaders: [String: String]

    public init(defaultHeaders: [String: String] = [:]) {
        self.defaultHeaders = defaultHeaders
    }

    public func build(from request: NetworkRequest) throws -> URLRequest {
        let url = try resolvedURL(for: request)
        var urlRequest = URLRequest(
            url: url,
            cachePolicy: request.cachePolicy,
            timeoutInterval: request.timeoutInterval
        )
        urlRequest.httpMethod = request.method.rawValue

        // Default headers first — per-request headers take precedence.
        defaultHeaders.forEach { urlRequest.setValue($1, forHTTPHeaderField: $0) }
        request.headers.forEach { urlRequest.setValue($1, forHTTPHeaderField: $0) }

        try applyBody(request.body, to: &urlRequest)
        return urlRequest
    }

    // MARK: - Private

    private func resolvedURL(for request: NetworkRequest) throws -> URL {
        guard !request.queryParameters.isEmpty else { return request.url }
        guard var components = URLComponents(url: request.url, resolvingAgainstBaseURL: true) else {
            throw NexNetError.invalidURL(request.url.absoluteString)
        }
        var items = components.queryItems ?? []
        request.queryParameters.sorted { $0.key < $1.key }.forEach {
            items.append(URLQueryItem(name: $0.key, value: $0.value))
        }
        components.queryItems = items
        guard let url = components.url else {
            throw NexNetError.invalidURL(request.url.absoluteString)
        }
        return url
    }

    private func applyBody(_ body: RequestBody, to request: inout URLRequest) throws {
        switch body {
        case .empty:
            break

        case .json(let data):
            request.httpBody = data
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            }

        case .raw(let data, let contentType):
            request.httpBody = data
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")

        case .formURLEncoded(let params):
            var components = URLComponents()
            components.queryItems = params.sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
            request.httpBody = components.query?.data(using: .utf8)
            request.setValue(
                "application/x-www-form-urlencoded; charset=utf-8",
                forHTTPHeaderField: "Content-Type"
            )

        case .multipart(let formData):
            request.httpBody = try buildMultipartBody(formData)
            request.setValue(
                "multipart/form-data; boundary=\(formData.boundary)",
                forHTTPHeaderField: "Content-Type"
            )
        }
    }

    private func buildMultipartBody(_ form: MultipartFormData) throws -> Data {
        var body = Data()
        let crlf = "\r\n"

        for part in form.parts {
            body.append("--\(form.boundary)\(crlf)")
            var disposition = "Content-Disposition: form-data; name=\"\(part.name)\""
            if let filename = part.filename { disposition += "; filename=\"\(filename)\"" }
            body.append("\(disposition)\(crlf)")
            if let mimeType = part.mimeType {
                body.append("Content-Type: \(mimeType)\(crlf)")
            }
            body.append(crlf)
            body.append(part.data)
            body.append(crlf)
        }
        body.append("--\(form.boundary)--\(crlf)")
        return body
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) { append(data) }
    }
}
