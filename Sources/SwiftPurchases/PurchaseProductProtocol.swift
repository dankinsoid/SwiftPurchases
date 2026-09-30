import Foundation

/// Represents a purchasable product
public protocol PurchaseProductProtocol<Value>: Sendable {

    /// The type representing the state
    associatedtype Value: Codable & Sendable

    /// The initial value before any purchase is made.
    var valueBeforePurchase: Value { get }
}

extension PurchaseProductProtocol where Value == Bool {

    public var valueBeforePurchase: Bool { false }
}
