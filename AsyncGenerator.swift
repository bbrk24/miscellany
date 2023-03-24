internal protocol AsyncGeneratorProtocol<Element>: AsyncSequence, AsyncIteratorProtocol, Actor
where AsyncIterator == Self {
    func setContinuation(_ continuation: CheckedContinuation<Void, Never>)
}

extension AsyncGeneratorProtocol {
    public nonisolated func makeAsyncIterator() -> Self {
        return self
    }
}

public final class Yield<Element: Sendable, Failure: Error> {
    internal var continuation: CheckedContinuation<Element?, Failure>?
    private unowned var parent: any AsyncGeneratorProtocol<Element>

    internal init(parent: some AsyncGeneratorProtocol<Element>) {
        self.parent = parent
    }

    public func callAsFunction(_ value: Element) async {
        await withCheckedContinuation { continuation in
            Task {
                await self.parent.setContinuation(continuation)
                self.continuation?.resume(returning: value)
                self.continuation = nil
            }
        }
    }
}

public actor AsyncGenerator<Element: Sendable>: AsyncGeneratorProtocol {
    private let callback: @Sendable (Yield<Element, Never>) async -> Void
    private var continuation: CheckedContinuation<Void, Never>?
    private lazy var yield: Yield<Element, Never> = .init(parent: self)

    public init(callback: @escaping @Sendable (Yield<Element, Never>) async -> Void) {
        self.callback = callback
    }

    internal func setContinuation(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    public func next() async -> Element? {
        return await withCheckedContinuation {
            yield.continuation = $0
            if let continuation = self.continuation {
                continuation.resume()
            } else {
                Task {
                    await self.callback(yield)
                    yield.continuation?.resume(returning: nil)
                }
            }
        }
    }
}

public actor AsyncThrowingGenerator<Element: Sendable>: AsyncGeneratorProtocol {
    private let callback: @Sendable (Yield<Element, Error>) async throws -> Void
    private var continuation: CheckedContinuation<Void, Never>?
    private lazy var yield: Yield<Element, Error> = .init(parent: self)

    public init(callback: @escaping @Sendable (Yield<Element, Error>) async throws -> Void) {
        self.callback = callback
    }

    internal func setContinuation(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    public func next() async throws -> Element? {
        return try await withCheckedThrowingContinuation {
            yield.continuation = $0
            if let continuation = self.continuation {
                continuation.resume()
            } else {
                Task {
                    do {
                        try await self.callback(yield)
                        yield.continuation?.resume(returning: nil)
                    } catch {
                        yield.continuation?.resume(throwing: error)
                    }
                }
            }
        }
    }
}
