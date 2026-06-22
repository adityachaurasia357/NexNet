//
//  NexNet.swift
//  NexNet
//
//  Created by Aditya Chaurasia on 22/06/26.
//
//  Public entry point for the NexNet networking framework.
//  After `import NexNet`, all public types are available directly.
//  Use `NetworkManager.shared` for the default instance, or create
//  a custom instance via `NetworkManager(configuration:)`.
//

import Foundation

// MARK: - Framework Version

/// Namespace for NexNet version constants.
public enum NexNetVersion {
    /// The current semantic version string of the NexNet framework (e.g. `"1.0.0"`).
    public static let current = "1.0.0"
}

// MARK: - Global Shorthand

/// A ready-to-use handle for the default shared `NetworkManager`.
///
///     let response: NetworkResponse<User> = try await NN.request(req)
///
public let NN = NetworkManager.shared
