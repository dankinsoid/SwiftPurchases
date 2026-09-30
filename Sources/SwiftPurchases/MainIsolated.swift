import Foundation

@propertyWrapper
final class MainIsolated<Value> {

	private var value: Value

	init(wrappedValue: Value) {
		self.value = wrappedValue
	}

	var wrappedValue: Value {
		get {
			if Thread.isMainThread {
				return value
			} else {
				return DispatchQueue.main.sync {
					 value
				}
			}
		}
	}

	func modify<T>(_ transform: (inout Value) -> T) -> T {
		if Thread.isMainThread {
			return transform(&value)
		} else {
			return DispatchQueue.main.sync {
				transform(&value)
			}
		}
	}
}

extension MainIsolated: @unchecked Sendable where Value: Sendable {}
