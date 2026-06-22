//
//  RetryPolicyTests.swift
//  NexNetTests
//
//  Created by Aditya Chaurasia on 22/06/2026.
//
//  Pure-logic tests for RetryPolicy — no networking required.
//

import Testing
@testable import NexNet

@Suite("RetryPolicy")
struct RetryPolicyTests {

    // MARK: - Preset policies

    @Test(".none has maxAttempts == 0")
    func noneHasZeroAttempts() {
        #expect(RetryPolicy.none.maxAttempts == 0)
    }

    @Test(".default has maxAttempts == 3")
    func defaultHasThreeAttempts() {
        #expect(RetryPolicy.default.maxAttempts == 3)
    }

    // MARK: - Constant backoff

    @Test("Constant strategy returns the same delay for every attempt")
    func constantDelay() {
        let policy = RetryPolicy(maxAttempts: 5, backoffStrategy: .constant(2.5))
        for attempt in 1...5 {
            #expect(policy.delay(for: attempt) == 2.5,
                    "Expected 2.5 s on attempt \(attempt)")
        }
    }

    @Test("Constant(0) returns zero delay")
    func constantZeroDelay() {
        let policy = RetryPolicy(maxAttempts: 3, backoffStrategy: .constant(0))
        #expect(policy.delay(for: 1) == 0)
        #expect(policy.delay(for: 3) == 0)
    }

    // MARK: - Linear backoff

    @Test("Linear strategy grows as base × attemptNumber")
    func linearDelay() {
        let policy = RetryPolicy(maxAttempts: 4, backoffStrategy: .linear(base: 2.0))
        #expect(policy.delay(for: 1) == 2.0)
        #expect(policy.delay(for: 2) == 4.0)
        #expect(policy.delay(for: 3) == 6.0)
        #expect(policy.delay(for: 4) == 8.0)
    }

    // MARK: - Exponential backoff

    @Test("Exponential strategy grows as base × multiplier^(attempt-1)")
    func exponentialDelay() {
        let policy = RetryPolicy(maxAttempts: 4,
                                 backoffStrategy: .exponential(base: 1.0, multiplier: 2.0))
        // attempt 1: 1.0 × 2^0 = 1.0
        // attempt 2: 1.0 × 2^1 = 2.0
        // attempt 3: 1.0 × 2^2 = 4.0
        // attempt 4: 1.0 × 2^3 = 8.0
        #expect(policy.delay(for: 1) == 1.0)
        #expect(policy.delay(for: 2) == 2.0)
        #expect(policy.delay(for: 3) == 4.0)
        #expect(policy.delay(for: 4) == 8.0)
    }

    @Test("Default preset uses exponential 1 s × 2.0")
    func defaultPresetIsExponential() {
        let policy = RetryPolicy.default
        #expect(policy.delay(for: 1) == 1.0)
        #expect(policy.delay(for: 2) == 2.0)
        #expect(policy.delay(for: 3) == 4.0)
    }

    @Test("Exponential delay with multiplier 3.0 triples each attempt")
    func exponentialMultiplierThree() {
        let policy = RetryPolicy(maxAttempts: 3,
                                 backoffStrategy: .exponential(base: 1.0, multiplier: 3.0))
        #expect(policy.delay(for: 1) == 1.0)
        #expect(policy.delay(for: 2) == 3.0)
        #expect(policy.delay(for: 3) == 9.0)
    }
}
