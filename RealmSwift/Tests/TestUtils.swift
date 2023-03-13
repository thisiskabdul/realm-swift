////////////////////////////////////////////////////////////////////////////
//
// Copyright 2022 Realm Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
////////////////////////////////////////////////////////////////////////////

import Foundation
import RealmSwift
import XCTest

#if canImport(RealmTestSupport)
import RealmTestSupport
#endif

@available(macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *)
@propertyWrapper
public class Locked<T>: @unchecked Sendable {
    private var value: T
    private let lock: os_unfair_lock_t = .allocate(capacity: 1)

    public init(wrappedValue: T) {
        value = wrappedValue
        lock.initialize(to: os_unfair_lock())
    }

    convenience public init(_ wrappedValue: T) {
        self.init(wrappedValue: wrappedValue)
    }

    public var wrappedValue: T {
        get {
            os_unfair_lock_lock(lock)
            let value = self.value
            os_unfair_lock_unlock(lock)
            return value
        }
        set {
            os_unfair_lock_lock(lock)
            value = newValue
            os_unfair_lock_unlock(lock)
        }
    }

    // A workaround for https://github.com/apple/swift/issues/61358
    // @Sendable property wrappers don't actually work currently, including
    // when capturing the property wrapper itself (i.e. with _foo). Capturing
    // the projected value does work, though.
    public var projectedValue: Locked<T> {
        self
    }
}

public extension XCTestCase {
    /// Check whether two test objects are equal (refer to the same row in the same Realm), even if their models
    /// don't define a primary key.
    func assertEqual<O: Object>(_ o1: O?, _ o2: O?, fileName: StaticString = #file, lineNumber: UInt = #line) {
        if o1 == nil && o2 == nil {
            return
        }
        if let o1 = o1, let o2 = o2, o1.isSameObject(as: o2) {
            return
        }
        XCTFail("Objects expected to be equal, but weren't. First: \(String(describing: o1)), "
            + "second: \(String(describing: o2))", file: (fileName), line: lineNumber)
    }

    /// Check whether two collections containing Realm objects are equal.
    func assertEqual<C: Collection>(_ c1: C, _ c2: C, fileName: StaticString = #file, lineNumber: UInt = #line)
        where C.Iterator.Element: Object {
            XCTAssertEqual(c1.count, c2.count, "Collection counts were incorrect", file: (fileName), line: lineNumber)
            for (o1, o2) in zip(c1, c2) {
                assertEqual(o1, o2, fileName: fileName, lineNumber: lineNumber)
            }
    }

    func assertEqual<T: Equatable>(_ expected: [T?], _ actual: [T?], file: StaticString = #file, line: UInt = #line) {
        if expected.count != actual.count {
            XCTFail("assertEqual failed: (\"\(expected)\") is not equal to (\"\(actual)\")",
                file: (file), line: line)
            return
        }

        XCTAssertEqual(expected.count, actual.count, "Collection counts were incorrect", file: (file), line: line)
        for (e, a) in zip(expected, actual) where e != a {
            XCTFail("assertEqual failed: (\"\(expected)\") is not equal to (\"\(actual)\")",
                file: (file), line: line)
            return
        }
    }

    func assertSucceeds(message: String? = nil, fileName: StaticString = #file,
                        lineNumber: UInt = #line, block: () throws -> Void) {
        do {
            try block()
        } catch {
            XCTFail("Expected no error, but instead caught <\(error)>.",
                file: (fileName), line: lineNumber)
        }
    }

    func assertFails<T>(_ expectedError: Realm.Error.Code, _ message: String? = nil,
                        fileName: StaticString = #file, lineNumber: UInt = #line,
                        block: () throws -> T) {
        do {
            _ = try autoreleasepool(invoking: block)
            XCTFail("Expected to catch <\(expectedError)>, but no error was thrown.",
                file: fileName, line: lineNumber)
        } catch let e as Realm.Error where e.code == expectedError {
            if message != nil {
                XCTAssertEqual(e.localizedDescription, message, file: fileName, line: lineNumber)
            }
        } catch {
            XCTFail("Expected to catch <\(expectedError)>, but instead caught <\(error)>.",
                file: fileName, line: lineNumber)
        }
    }

    func assertFails<T>(_ expectedError: Realm.Error.Code, _ file: URL, _ message: String,
                        fileName: StaticString = #file, lineNumber: UInt = #line,
                        block: () throws -> T) {
        do {
            _ = try autoreleasepool(invoking: block)
            XCTFail("Expected to catch <\(expectedError)>, but no error was thrown.",
                file: fileName, line: lineNumber)
        } catch let e as Realm.Error where e.code == expectedError {
            XCTAssertEqual(e.localizedDescription, message, file: fileName, line: lineNumber)
            XCTAssertEqual(e.fileURL, file, file: fileName, line: lineNumber)
        } catch {
            XCTFail("Expected to catch <\(expectedError)>, but instead caught <\(error)>.",
                file: fileName, line: lineNumber)
        }
    }

    func assertFails<T>(_ expectedError: Error, _ message: String? = nil,
                        fileName: StaticString = #file, lineNumber: UInt = #line,
                        block: () throws -> T) {
        do {
            _ = try autoreleasepool(invoking: block)
            XCTFail("Expected to catch <\(expectedError)>, but no error was thrown.",
                file: fileName, line: lineNumber)
        } catch let e where e._code == expectedError._code {
            // Success!
        } catch {
            XCTFail("Expected to catch <\(expectedError)>, but instead caught <\(error)>.",
                file: fileName, line: lineNumber)
        }
    }

    func assertNil<T>(block: @autoclosure() -> T?, _ message: String? = nil,
                      fileName: StaticString = #file, lineNumber: UInt = #line) {
        XCTAssert(block() == nil, message ?? "", file: (fileName), line: lineNumber)
    }

    func assertMatches(_ block: @autoclosure () -> String, _ regexString: String, _ message: String? = nil,
                       fileName: String = #file, lineNumber: UInt = #line) {
        RLMAssertMatches(self, block, regexString, message, fileName, lineNumber)
    }

    /// Check that a `MutableSet` contains all expected elements.
    func assertSetContains<T, U>(_ set: MutableSet<T>, keyPath: KeyPath<T, U>, items: [U]) where U: Hashable {
        var itemMap = Dictionary(uniqueKeysWithValues: items.map { ($0, false)})
        set.map { $0[keyPath: keyPath]}.forEach {
            itemMap[$0] = items.contains($0)
        }
        // ensure all items are present in the set.
        XCTAssertFalse(itemMap.values.contains(false))
    }

    /// Check that an `AnyRealmCollection` contains all expected elements.
    func assertAnyRealmCollectionContains<T, U>(_ set: AnyRealmCollection<T>, keyPath: KeyPath<T, U>, items: [U]) where U: Hashable {
        var itemMap = Dictionary(uniqueKeysWithValues: items.map { ($0, false)})
        set.map { $0[keyPath: keyPath]}.forEach {
            itemMap[$0] = items.contains($0)
        }
        // ensure all items are present in the set.
        XCTAssertFalse(itemMap.values.contains(false))
    }
}

@_unsafeInheritExecutor
public func assertThrowsErrorAsync<T, E: Equatable & Error>(
    _ expression: @autoclosure () async throws -> T,
    _ expectedError: E,
    file: StaticString = #filePath, line: UInt = #line) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw error \(expectedError)", file: file, line: line)
    } catch let error as E {
        XCTAssertEqual(error, expectedError, file: file, line: line)
    } catch {
        XCTFail("Expected expression to throw error \(expectedError) but got \(error)", file: file, line: line)
    }
}

// Fork, call an expression which should hit a precondition failure in the child
// process, and then verify that the expected failure message was printed. Note
// that Swift and Foundation do not support fork(), so anything which does more
// than a very limited amount of work before the precondition failure is very
// likely to break.
@_unsafeInheritExecutor
public func assertPreconditionFailure(_ message: String, _ expression: () async throws -> Void,
                                      file: StaticString = #filePath, line: UInt = #line) async throws {
    let pipe = Pipe()

    let pid = RLMFork()
    if (pid == -1) {
        return XCTFail("Failed to fork for test", file: file, line: line)
    }

    if (pid == 0) {
        // In child process
        // Point stdout and stderr at our pipe
        let fd = pipe.fileHandleForWriting.fileDescriptor
        while dup2(fd, STDOUT_FILENO) == -1 && errno == EINTR {}
        while dup2(fd, STDERR_FILENO) == -1 && errno == EINTR {}
        try await expression()
        exit(0)
    }

    try pipe.fileHandleForWriting.close()
    while true {
        var status: Int32 = 0
        let ret = waitpid(pid, &status, 0)
        if ret == -1 && errno == EINTR {
            continue
        }
        guard ret > 0 else {
            return XCTFail("Failed to wait for child process to exit? errno: \(errno)", file: file, line: line)
        }
        guard status != 0 else {
            return XCTFail("Expected child process to crash with message \"\(message)\", but it exited cleanly", file: file, line: line)
        }
        break
    }

    guard let data = try pipe.fileHandleForReading.readToEnd() else {
        return XCTFail("Expected child process to crash with message \"\(message)\", but it exited without printing anything", file: file, line: line)
    }
    guard let str = String(data: data, encoding: .utf8) else {
        return XCTFail("Expected child process to crash with message \"\(message)\", but it did not print valid utf-8", file: file, line: line)
    }

    if !str.contains("Precondition failed: \(message)") {
        XCTFail("Expected \"\(str)\" to contain \"\(message)\")", file: file, line: line)
    }
}
