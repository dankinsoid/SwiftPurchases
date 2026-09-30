import Foundation

/// Protocol for products that have a default purchase option.
public protocol SinglePurchaseProductProtocol<Value>: PurchaseProductProtocol {

    /// The default purchase option for this product.
    var product: PurchaseOption<Self> { get }
}
