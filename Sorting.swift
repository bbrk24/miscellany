import Foundation

public func radixSort<T: UnsignedInteger>(_ arr: inout [T], radix: T, maxValue: T? = nil) {
    guard let maxValue = maxValue ?? arr.max() else { return }
    var doneRadix: T = 1
    while true {
        var buckets = Array(repeating: [T](), count: Int(radix))

        for el in arr {
            buckets[Int((el / doneRadix) % radix)].append(el)
        }

        arr = buckets.flatMap { $0 }
        doneRadix *= radix

        if doneRadix >= maxValue {
            return
        }
    }
}


// Unlike some other lazy sequences, which perform the work only as needed, this prepares the
// entire sorted section on initialization. This allows it to operate in O(m log n) time, rather
// than O(mn).
public struct SortedPrefix<Element: Comparable>: LazySequenceProtocol {
    private let maxCount: Int
    private var buffer: [Element]

    public var underestimatedCount: Int {
        return Swift.max(maxCount, buffer.count)
    }

    init(_ base: some Collection<Element>, maxCount: Int) {
        precondition(maxCount >= 0)
        self.maxCount = maxCount

        if maxCount == 0 || base.isEmpty {
            buffer = .init()
            return
        }
        if maxCount == 1 {
            buffer = [base.min()!]
            return 
        }

        let baseCount = base.count
        if baseCount <= 64 || maxCount >= baseCount / 2 {
            // If the list is small or we need most of it, just sort the whole thing
            // FIXME: Maybe use a larger fraction than 1/2?
            buffer = base.sorted()
        } else if maxCount <= 64 {
            buffer = [base.first!]
            partialInsertionSort(base)
        } else {
            buffer = Self.partialIntroSort(
                Array(base),
                requiredCount: maxCount,
                maxDepth: Int(ceil(log2(Double(baseCount))))
            )
        }
    }

    private mutating func partialInsertionSort(_ base: some Collection<Element>) {
        func insertIntoBuffer(_ el: Element) {
            // Fast paths
            if el >= buffer.last! {
                buffer.append(el)
                return
            }
            if el <= buffer.first! {
                buffer.insert(el, at: 0)
                return
            }
            // Binary search
            var start = 0, end = buffer.count
            while start != end - 1 {
                let mid = (start + end) / 2
                if buffer[mid] <= el {
                    start = mid
                } else {
                    end = mid
                }
            }
            // Actually insert
            if buffer[start] >= el {
                buffer.insert(el, at: start)
            } else {
                buffer.insert(el, at: start + 1)
            }
        }

        for el in base.dropFirst() {
            if buffer.count < maxCount || el < buffer.last! {
                insertIntoBuffer(el)
                if buffer.count > maxCount {
                    buffer.popLast()
                }
            }
        }
    }

    private static func partialIntroSort(
        _ arr: __owned [Element],
        requiredCount: Int,
        maxDepth: Int
    ) -> [Element] {
        if requiredCount < 1 {
            return .init()
        }
        
        if requiredCount == arr.count || maxDepth == 0 || arr.count <= 7 {
            // If we need the whole thing, can't recurse deeper, or sorting is trivial,
            // just sort the whole thing.
            return arr.sorted()
        }

        let pivot = arr[arr.count / 2]
        var copy = arr
        let pivotIndex = copy.partition { $0 > pivot }

        let right = partialIntroSort(
            Array(copy[pivotIndex...]),
            requiredCount: requiredCount - pivotIndex,
            maxDepth: maxDepth - 1
        )
        var left = partialIntroSort(
            Array(copy[..<pivotIndex]),
            requiredCount: Swift.min(pivotIndex, requiredCount),
            maxDepth: maxDepth - 1
        )
        left += right
        return left
    }

    public func makeIterator() -> some IteratorProtocol<Element> {
        return buffer.prefix(self.maxCount).makeIterator()
    }
}

