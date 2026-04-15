struct Box[T: Copyable & Movable & ImplicitlyDestructible](
    Copyable, Movable, ImplicitlyDestructible
):
    """Heap-indirected optional value used for recursive message fields."""

    var _storage: List[Self.T]

    def __init__(out self):
        self._storage = List[Self.T]()

    def __init__(out self, var value: Self.T):
        self._storage = List[Self.T]()
        self._storage.append(value^)

    def __bool__(self) -> Bool:
        return len(self._storage) > 0

    def has_value(self) -> Bool:
        return len(self._storage) > 0

    def value(ref self) -> ref [self._storage] Self.T:
        return self._storage[0]
