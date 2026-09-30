import Foundation
import StoreKit

/// Represents a specific purchase option for a product.
public struct PurchaseOption<ProductType: PurchaseProductProtocol>: Sendable {

    /// The App Store product identifier.
    public let productID: String

    /// Closure called when the purchase is made.
    public let buy: @Sendable (Transaction, ProductType, inout ProductType.Value) -> Void

    /// Closure called when the purchase expires.
    public let check: @Sendable (Date, ProductType, inout ProductType.Value) -> Void

    public init(
        productID: String,
        buy: @escaping @Sendable (Transaction, ProductType, inout ProductType.Value) -> Void,
				check: @escaping @Sendable (Date, ProductType, inout ProductType.Value) -> Void = { _, _, _ in }
    ) {
        self.productID = productID
        self.buy = buy
        self.check = check
    }
}

extension PurchaseOption where ProductType.Value == Bool {

    /// Convenience initializer for boolean-valued products.
    public init(
        productID: String,
        accessDuration: TimeInterval? = nil
    ) {
        self.productID = productID
        self.accessDuration = accessDuration
        self.buy = { _, _, value in value = true }
        self.check = { _, _, value in value = false }
    }
}
