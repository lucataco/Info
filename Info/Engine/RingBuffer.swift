/// A fixed-capacity ring buffer used for in-memory metric history.
///
/// History lives only here — never on disk. This is the core of why Info is so
/// much lighter than Stats, which persisted every sample to LevelDB.
struct RingBuffer<Element: Sendable>: Sendable {
    private var storage: [Element] = []
    private var head = 0
    let capacity: Int

    init(capacity: Int) {
        self.capacity = max(1, capacity)
        self.storage.reserveCapacity(self.capacity)
    }

    var count: Int { storage.count }
    var isEmpty: Bool { storage.isEmpty }

    mutating func append(_ element: Element) {
        if storage.count < capacity {
            storage.append(element)
        } else {
            storage[head] = element
            head = (head + 1) % capacity
        }
    }

    /// Elements in chronological order (oldest first, newest last).
    var values: [Element] {
        guard storage.count == capacity else { return storage }
        return Array(storage[head...] + storage[..<head])
    }

    var last: Element? { values.last }
}
