
func anyPurchases() {

	// 1. Consumable repeetable purchase
	enum Coins: PurchaseProductProtocol {

		typealias Value = Int
	
		let beforePurchaseValue: Int = 0
	}

	extension PurchaseOption<CoinsPurchase> {

		static var oneHundred: PurchaseOption<Coins> {
			PurchaseOption(
				id: "com.app.coins.100",
				apply: { $0 += 100 }
			)
		}

		static var fiveHundred: PurchaseOption<Coins> {
			PurchaseOption(
				id: "com.app.coins.500",
				apply: { $0 += 500 }
			)
		}
	}

	let coins = Inventory(Coins())
	coins.value
	coins.publisher // itself is a publisher?
	try await coins.buy(.oneHundred)
	try await coins.buy(.fiveHundreds)
	let product = try await PurchaseOption.oneHundred.product
  // or?
	try await IAPService.shared.buy(PurchaseOption.oneHundred)
	try await IAPService.shared.product(PurchaseOption.oneHundred)

	// 2. Non-consumable one-time purchase
	enum PremiumPurchase: SinglePurchaseProductProtocol {

		typealias Value = Bool
		let beforePurchaseValue: Bool = false
		let product: PurchaseOption<PremiumPurchase> = PurchaseOption(
			id: "com.app.premium",
			apply: { $0 = true }
		)
	}

	let premium = Inventory<PremiumPurchase>()
	premium.value
	try await premium.buy()

	/// 3.
	struct TransferPurchase: SinglePurchaseProductProtocol {
		
		let source: ServiceType
		let target: ServiceType
		let product: PurchaseOption<TransferPurchase>
		
		init(productID: String, source: ServiceType, target: ServiceType) {
			self.source = source
			self.target = target
			self.product = PurchaseOption(id: id)
		}
	}
	
	Purchase(TransferPurchase(productID: "appleMusic_spotify", source: .appleMusic, target: .spotify))

	///
	struct TransferPurchase: PurchaseProductProtocol {

		struct Value: Codable, Sendable {
			var source: ServiceType
			var target: ServiceType
		}
	}

	extension PurchaseOption<TransferPurchase> {

		static func transfer(
			id: String,
			from source: ServiceType,
			to target: ServiceType
		) -> PurchaseOption<TransferPurchase> {
			PurchaseOption(
				id: id,
				buy: { $0 = .init(source: source, target: target) },
				expire: {  }
			)
		}
	}
}

public protocol PurchaseProductProtocol<Value>: Sendable {

	associatedtype Value: Codable & Sendable = Bool
	var valueBeforePurchase: Value { get }
}

extension PurchaseProductProtocol where Value == Bool {

	public var valueBeforePurchase: Bool { false }
}

public protocol SinglePurchaseProductProtocol<Value>: PurchaseProductProtocol {

	var product: PurchaseOption<Self> { get }
}


public struct PurchaseOption<ProductType: PurchaseProductProtocol>: Sendable {

	public let productID: String
	public let accessDuration: TimeInterval?
	public let buy: @Sendable (Date, ProductType, inout ProductType.Value) -> Void
	public let expire: @Sendable (Date, ProductType, inout ProductType.Value) -> Void

	public init(
		productID: String,
		accessDuration: TimeInterval?,
		buy: @escaping @Sendable (Date, ProductType, inout ProductType.Value) -> Void,
		expire: @escaping @Sendable (Date, ProductType, inout ProductType.Value) -> Void
	) {
		self.productID = productID
		self.accessDuration = accessDuration
		self.buy = buy
		self.expire = expire
	}
}
