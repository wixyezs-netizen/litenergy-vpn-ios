// SPDX-License-Identifier: GPL-3.0-or-later
// Из sing-box-for-apple (Library/Network/Extension+RunBlocking.swift), GPL-3.0.

import Foundation

func runBlocking<T>(_ block: @escaping () async -> T) -> T {
    let semaphore = DispatchSemaphore(value: 0)
    let box = ResultBox<T>()
    Task.detached(priority: .userInitiated) {
        let value = await block()
        box.result0 = value
        semaphore.signal()
    }
    semaphore.wait()
    return box.result0
}

func runBlocking<T>(_ tBlock: @escaping () async throws -> T) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    let box = ResultBox<T>()
    Task.detached(priority: .userInitiated) {
        do {
            let value = try await tBlock()
            box.result = .success(value)
        } catch {
            box.result = .failure(error)
        }
        semaphore.signal()
    }
    semaphore.wait()
    return try box.result.get()
}

private final class ResultBox<T> {
    var result: Result<T, Error>!
    var result0: T!
}
