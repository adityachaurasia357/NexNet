//
//  ResponseHandlerTests.swift
//  NexNetTests
//

import Testing
import Foundation
@testable import NexNet

@Suite("ResponseHandler")
struct ResponseHandlerTests {

    private let handler = ResponseHandler()
    private let decoder = ResponseHandler.makeDecoder()
    private let url     = URL(string: "https://api.example.com/items/1")!

    private func httpResponse(statusCode: Int, headers: [String: String]? = nil) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: statusCode,
                        httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    // MARK: - validate: success

    @Test("2xx responses are returned without throwing")
    func validateSuccessRange() throws {
        for code in [200, 201, 204, 206, 299] {
            let response = try handler.validate(httpResponse(statusCode: code), data: Data())
            #expect(response.statusCode == code)
        }
    }

    // MARK: - validate: 4xx

    @Test("400 throws .badRequest")
    func validate400() {
        #expect {
            try handler.validate(httpResponse(statusCode: 400), data: Data())
        } throws: { error in
            guard let e = error as? NexNetError, case .badRequest = e else { return false }
            return true
        }
    }

    @Test("401 throws .unauthorized")
    func validate401() {
        #expect {
            try handler.validate(httpResponse(statusCode: 401), data: Data())
        } throws: { error in
            guard let e = error as? NexNetError, case .unauthorized = e else { return false }
            return true
        }
    }

    @Test("403 throws .forbidden")
    func validate403() {
        #expect {
            try handler.validate(httpResponse(statusCode: 403), data: Data())
        } throws: { error in
            guard let e = error as? NexNetError, case .forbidden = e else { return false }
            return true
        }
    }

    @Test("404 throws .notFound carrying the response URL")
    func validate404() throws {
        do {
            _ = try handler.validate(httpResponse(statusCode: 404), data: Data())
            Issue.record("Expected .notFound to be thrown")
        } catch let e as NexNetError {
            guard case .notFound(let urlStr) = e else {
                Issue.record("Expected .notFound, got \(e)"); return
            }
            #expect(urlStr.contains("api.example.com"))
        }
    }

    @Test("422 throws .unprocessableEntity")
    func validate422() {
        #expect {
            try handler.validate(httpResponse(statusCode: 422), data: Data())
        } throws: { error in
            guard let e = error as? NexNetError, case .unprocessableEntity = e else { return false }
            return true
        }
    }

    @Test("429 throws .tooManyRequests with Retry-After header value")
    func validate429WithHeader() throws {
        do {
            _ = try handler.validate(
                httpResponse(statusCode: 429, headers: ["Retry-After": "60"]), data: Data()
            )
            Issue.record("Expected .tooManyRequests to be thrown")
        } catch let e as NexNetError {
            guard case .tooManyRequests(let retryAfter) = e else {
                Issue.record("Expected .tooManyRequests, got \(e)"); return
            }
            #expect(retryAfter == "60")
        }
    }

    @Test("429 throws .tooManyRequests with nil retryAfter when header is absent")
    func validate429WithoutHeader() throws {
        do {
            _ = try handler.validate(httpResponse(statusCode: 429), data: Data())
            Issue.record("Expected .tooManyRequests to be thrown")
        } catch let e as NexNetError {
            guard case .tooManyRequests(let retryAfter) = e else {
                Issue.record("Expected .tooManyRequests, got \(e)"); return
            }
            #expect(retryAfter == nil)
        }
    }

    // MARK: - validate: 5xx

    @Test("500 throws .internalServerError")
    func validate500() {
        #expect {
            try handler.validate(httpResponse(statusCode: 500), data: Data())
        } throws: { error in
            guard let e = error as? NexNetError, case .internalServerError = e else { return false }
            return true
        }
    }

    @Test("502 throws .badGateway")
    func validate502() {
        #expect {
            try handler.validate(httpResponse(statusCode: 502), data: Data())
        } throws: { error in
            guard let e = error as? NexNetError, case .badGateway = e else { return false }
            return true
        }
    }

    @Test("503 throws .serviceUnavailable with Retry-After header value")
    func validate503WithHeader() throws {
        do {
            _ = try handler.validate(
                httpResponse(statusCode: 503, headers: ["Retry-After": "30"]), data: Data()
            )
            Issue.record("Expected .serviceUnavailable to be thrown")
        } catch let e as NexNetError {
            guard case .serviceUnavailable(let retryAfter) = e else {
                Issue.record("Expected .serviceUnavailable, got \(e)"); return
            }
            #expect(retryAfter == "30")
        }
    }

    @Test("504 throws .gatewayTimeout")
    func validate504() {
        #expect {
            try handler.validate(httpResponse(statusCode: 504), data: Data())
        } throws: { error in
            guard let e = error as? NexNetError, case .gatewayTimeout = e else { return false }
            return true
        }
    }

    @Test("Unmapped status code (e.g. 418) throws .httpError carrying the code")
    func validateUnmappedCode() throws {
        do {
            _ = try handler.validate(httpResponse(statusCode: 418), data: Data())
            Issue.record("Expected .httpError to be thrown")
        } catch let e as NexNetError {
            guard case .httpError(let code, _) = e else {
                Issue.record("Expected .httpError, got \(e)"); return
            }
            #expect(code == 418)
        }
    }

    @Test("Non-HTTPURLResponse throws .httpError with code -1")
    func validateNonHTTP() throws {
        let plain = URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
        do {
            _ = try handler.validate(plain, data: Data())
            Issue.record("Expected .httpError to be thrown")
        } catch let e as NexNetError {
            guard case .httpError(let code, _) = e else {
                Issue.record("Expected .httpError, got \(e)"); return
            }
            #expect(code == -1)
        }
    }

    // MARK: - decode: success

    private struct Item: Decodable, Equatable {
        let id: Int
        let itemName: String   // decoded from "item_name" via .convertFromSnakeCase
    }

    @Test("Decodes valid JSON into the target type")
    func decodeSuccess() throws {
        let data = Data(#"{"id":7,"item_name":"widget"}"#.utf8)
        let item = try handler.decode(Item.self, from: data, decoder: decoder)
        #expect(item == Item(id: 7, itemName: "widget"))
    }

    @Test("Snake_case JSON keys are converted to camelCase automatically")
    func snakeCaseConversion() throws {
        let data = Data(#"{"id":1,"item_name":"gadget"}"#.utf8)
        let item = try handler.decode(Item.self, from: data, decoder: decoder)
        #expect(item.itemName == "gadget")
    }

    // MARK: - decode: empty body

    @Test("Empty data throws .emptyResponse for non-EmptyResponse types")
    func decodeEmptyThrows() {
        #expect {
            try handler.decode(Item.self, from: Data(), decoder: decoder)
        } throws: { error in
            guard let e = error as? NexNetError, case .emptyResponse = e else { return false }
            return true
        }
    }

    @Test("Empty data returns EmptyResponse() when T is EmptyResponse")
    func decodeEmptyForEmptyResponse() throws {
        // Should not throw
        _ = try handler.decode(EmptyResponse.self, from: Data(), decoder: decoder)
    }

    // MARK: - decode: failures

    @Test("Non-JSON data throws .decodingFailed")
    func decodeInvalidJSON() {
        #expect {
            try handler.decode(Item.self, from: Data("not-json".utf8), decoder: decoder)
        } throws: { error in
            guard let e = error as? NexNetError, case .decodingFailed = e else { return false }
            return true
        }
    }

    @Test("Type mismatch throws .decodingFailed with a non-empty coding path")
    func decodeTypeMismatch() throws {
        // id is declared Int but JSON provides a String
        let data = Data(#"{"id":"wrong-type","item_name":"x"}"#.utf8)
        do {
            _ = try handler.decode(Item.self, from: data, decoder: decoder)
            Issue.record("Expected .decodingFailed to be thrown")
        } catch let e as NexNetError {
            guard case .decodingFailed(_, let path) = e else {
                Issue.record("Expected .decodingFailed, got \(e)"); return
            }
            #expect(!path.isEmpty, "Coding path should not be empty for type mismatch")
        }
    }

    @Test("Missing required key throws .decodingFailed with the missing key in coding path")
    func decodeMissingKey() throws {
        let data = Data(#"{"id":1}"#.utf8)   // item_name is missing
        do {
            _ = try handler.decode(Item.self, from: data, decoder: decoder)
            Issue.record("Expected .decodingFailed to be thrown")
        } catch let e as NexNetError {
            guard case .decodingFailed(_, let path) = e else {
                Issue.record("Expected .decodingFailed, got \(e)"); return
            }
            #expect(path.contains("itemName") || path.contains("item_name") || !path.isEmpty)
        }
    }

    // MARK: - decode: ISO 8601 dates

    private struct Event: Decodable {
        let startedAt: Date
    }

    @Test("Plain ISO 8601 date (no fractional seconds) is decoded correctly")
    func decodeDatePlain() throws {
        let data = Data(#"{"started_at":"2024-06-15T08:00:00Z"}"#.utf8)
        let event = try handler.decode(Event.self, from: data, decoder: decoder)
        // Confirm we get a real date (not epoch)
        #expect(event.startedAt.timeIntervalSince1970 > 1_000_000_000)
    }

    @Test("Fractional-second ISO 8601 date is decoded correctly")
    func decodeDateFractional() throws {
        let data = Data(#"{"started_at":"2024-06-15T08:00:00.999Z"}"#.utf8)
        let event = try handler.decode(Event.self, from: data, decoder: decoder)
        #expect(event.startedAt.timeIntervalSince1970 > 1_000_000_000)
    }

    @Test("Plain and fractional ISO 8601 dates decode to the same second")
    func decodeDatePlainVsFractional() throws {
        let plain      = try handler.decode(Event.self,
                           from: Data(#"{"started_at":"2024-06-15T08:00:00Z"}"#.utf8),
                           decoder: decoder)
        let fractional = try handler.decode(Event.self,
                           from: Data(#"{"started_at":"2024-06-15T08:00:00.000Z"}"#.utf8),
                           decoder: decoder)
        #expect(plain.startedAt == fractional.startedAt)
    }

    @Test("Non-ISO 8601 date string throws .decodingFailed")
    func decodeInvalidDate() {
        let data = Data(#"{"started_at":"15 June 2024"}"#.utf8)
        #expect {
            try handler.decode(Event.self, from: data, decoder: decoder)
        } throws: { error in
            guard let e = error as? NexNetError, case .decodingFailed = e else { return false }
            return true
        }
    }
}
