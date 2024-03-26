// MARK: FullEnumMap
/// A dictionary-like type with enum keys that guarantees every case exists.
public protocol FullEnumMap<Key, Value>: ExpressibleByDictionaryLiteral, Collection, CustomReflectable, CustomDebugStringConvertible
where Key: CaseIterable, Element == (key: Key, value: Value) {
    associatedtype Values: Collection
        where Values.Element == Value

    var values: Values { get }

    init?(_ other: some Sequence<Element>)

    subscript(key: Key) -> Value { get set }
}

extension FullEnumMap {
    public init(dictionaryLiteral: (Key, Value)...) {
        guard let _self = Self(dictionaryLiteral) else {
            preconditionFailure("FullEnumMap requires all enum cases as keys")
        }
        self = _self
    }

    var customMirror: Mirror {
        return Mirror(
            self,
            children: self.map { (label: String(reflecting: $0.key), value: $0.value) },
            displayStyle: .dictionary   
        )
    }

    var debugDescription: String {
        var result = "["
        var isFirst = true

        for (key, value) in self {
            if isFirst {
                isFirst = false
            } else {
                result += ", "
            }

            result += String(reflecting: key) + ": " + String(reflecting: value)
        }

        return result + "]"
    }

    var count: Int { Key.allCases.count }

    public func toDictionary() -> Dictionary<Key, Value>
    where Key: Hashable {
        return Dictionary(uniqueKeysWithValues: self)
    }
}

extension Encodable
where Self: FullEnumMap, Key: CodingKey, Value: Encodable {
    func encode(to encoder: Encoder) throws {
        let container = encoder.container(keyedBy: Key.self)
        for (key, value) in self {
            try container.encode(value, forKey: key)
        }
    }
}

extension Decodable
where Self: FullEnumMap, Key: CodingKey, Value: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        self = .init(
            try Key.allCases.map {
                (key: $0, value: try container.decode(Value.self, forKey: $0))
            }
        )!
    }
}

// MARK: LinearEnumMap
/// An enum map that uses contiguous memory and provides very fast element access.
/// Requires that the enum is represented as consecutive integers starting at zero.
public struct LinearEnumMap<Key: CaseIterable & RawRepresentable, Value>: FullEnumMap, RandomAccessCollection
where Key.AllCases: RandomAccessCollection, Key.RawValue == Int {
    public private(set) var values: Array<Value>

    public var startIndex: Int { 0 }
    public var endIndex: Int { count }
    public var indices: Range<Int> { 0 ..< count }

    public init?(_ other: some Sequence<Element>) {
        assert(
            Key.allCases.sorted().elementsEqual(0 ..< Key.allCases.count),
            "LinearEnumMap requires keys to be consecutive integers from 0"
        )

        self.values = .init(unsafeUninitializedCapacity: Key.allCases.count) { (buffer, initializedCount) in
            var initializedIndices = Set<Int>()

            for (key, value) in other {
                buffer[key.rawValue] = value
                if initializedIndices.insert(key.rawValue).inserted {
                    initializedCount += 1
                }
            }
        }

        if self.values.count != Key.allCases.count {
            return nil
        }
    }

    public subscript(position: Int) -> Element {
        return (key: Key(rawValue: position)!, value: self.values[position])
    }

    public subscript(key: Key) -> Value {
        get {
            return self.values[key.rawValue]
        }
        set {
            self.values[key.rawValue] = newValue
        }
    }

    public func makeIterator() -> some Iterator<Element> {
        return self.values
            .enumerated()
            .lazy
            .map { (key: Key(rawValue: $0.offset)!, value: $0.element) }
            .makeIterator()
    }

    public func index(after i: Int) -> Int {
        assert(i < count)
        return i + 1
    }

    public func index(before i: Int) -> Int {
        assert(i > 0)
        return i - 1
    }
}

extension LinearEnumMap: Equatable
where Value: Equatable {
}

extension LinearEnumMap: Hashable
where Value: Hashable {
}

extension LinearEnumMap: Sendable
where Key: Sendable, Value: Sendable {
}

// MARK: EnumHashMap
/// A wrapper around a plain Dictionary that enforces fullness.
struct EnumHashMap<Key: CaseIterable & Hashable, Value>: FullEnumMap {
    public typealias Index = Dictionary<Key, Value>.Index

    private var storage: Dictionary<Key, Value>

    public var values: Dictionary<Key, Value>.Values { self.storage.values }
    public var startIndex: Index { self.storage.startIndex }
    public var endIndex: Index { self.storage.endIndex }

    public init?(_ other: some Sequence<Element>) {
        do {
            self.storage = try Dictionary(other) { _, _ in throw DuplicateError() }
        } catch {
            return nil
        }

        if self.storage.count != Key.allCases.count {
            return nil
        }
    }

    public subscript(key: Key) -> Value {
        get {
            return self.storage[key]!
        }
        set {
            self.storage[key] = newValue
        }
    }

    public subscript(position: Index) -> Element {
        return self.storage[position]
    }

    public func makeIterator() -> some Iterator<Element> {
        return self.storage.makeIterator()
    }

    public func index(after i: Index) -> Index {
        return self.storage.index(after: i)
    }

    private struct DuplicateError: Error {}
}

extension EnumHashMap: Equatable
where Value: Equatable {
}

extension EnumHashMap: Hashable
where Value: Hashable {
}

extension EnumHashMap: Sendable
where Key: Sendable, Value: Sendable {
}

// MARK: SlowContiguousEnumMap
/// Unlike other FullEnumMap types, this provides O(n) subscripting. However, it implements withContiguousStorageIfAvailable().
struct SlowContiguousEnumMap<Key: CaseIterable & Equatable, Value>: FullEnumMap, RandomAccessCollection {
    private var storage: ContiguousArray<Element>

    public var count: Int { storage.count }
    public var startIndex: Int { 0 }
    public var endIndex: Int { storage.endIndex }
    public var indices: Range<Int> { 0 ..< endIndex }
    public var values: some RandomAccessCollection<Value> { storage.lazy.map(\.1) }

    public init?(_ other: some Sequence<Element>) {
        self.storage = .init(other)

        if self.storage.count != Key.allCases.count {
            return nil
        }
    }

    public subscript(position: Int) -> Element {
        return self.storage[position]
    }

    public subscript(key: Key) -> Value {
        get {
            for element in self.storage {
                if element.key == key {
                    return value
                }
            }
            preconditionFailure()
        }
        set {
            for i in self.indices {
                if self.storage[i].key == key {
                    self.storage[i].value = newValue
                    return
                }
            }
            assertionFailure()
        }
    }

    public func withContiguousStorageIfAvailable<R>(_ body: (UnsafeBufferPointer<Element>) throws -> R) rethrows -> R? {
        return try self.storage.withContiguousStorageIfAvailable(body)
    }

    public func makeIterator() -> some Iterator<Element> {
        return self.storage.makeIterator()
    }

    public func index(after i: Int) -> Int {
        assert(i < count)
        return i + 1
    }

    public func index(before i: Int) -> Int {
        assert(i > 0)
        return i - 1
    }
}

extension SlowContiguousEnumMap: Sendable
where Key: Sendable, Value: Sendable {
}
