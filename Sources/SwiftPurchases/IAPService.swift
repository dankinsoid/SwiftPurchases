import Combine
import Foundation
import StoreKit

public final class IAPService: ObservableObject, Sendable {
	
	// MARK: Lifecycle
	
	public typealias ObjectWillChangePublisher = AnyPublisher<Void, Never>
	
	public static let shared = IAPService()
	
	private init() {}
	
	// MARK: Public
	
	public nonisolated var objectWillChange: ObjectWillChangePublisher {
		updater
			.merge(
				with: Publishers.Async { [weak self] in
					_ = try? await self?.fetchIfNeeded()
				}
			)
			.eraseToAnyPublisher()
	}
	
	public var debugPurchases: [String: Bool] {
		get {
			debugPurchasesStore
		}
		set {
			debugPurchasesStore = newValue
			updateProducts()
		}
	}
	
	private var debugPurchasesStore: [String: Bool]
	private var purchases: [String: IdentifiedArrayOf<IAPPurchase>]
	
	public var activeProducts: Set<String> {
		if isDevelopBuild {
			Set(
				purchases
					.filter { $0.value.contains(where: \.isActive) }
					.keys
			)
			.union(debugPurchases.filter(\.value).map(\.key))
			.union(boughtPurchases.value)
			.intersection(productsIDs())
			.filter { debugPurchases[$0] != false }
		} else {
			Set(
				purchases
					.filter { $0.value.contains(where: \.isActive) }
					.keys
			)
			.union(boughtPurchases.value)
			.intersection(productsIDs())
		}
	}
	
	// private lazy var logger = Logger(label: "IAPService")
	// private lazy var analytics = Analytics()
	// private lazy var configs = Configs()
	private var productsIDs: () -> Set<String> = { [] }
	// private var isValid: (_ id: String, _ purchaseDate: Date) -> (Bool, Date?) = { _, _ in (true, nil) }
	// private var event: (String) -> Analytics.Event = { Analytics.Event($0) }
	private var iapProducts: IdentifiedArrayOf<IAPProduct>?
	private var transactionsListener: Task<Void, Error>?
	
	public var activeProductsPublisher: AnyPublisher<Set<String>, Never> {
		updater
			.prepend(())
			.map { self.activeProducts }
			.eraseToAnyPublisher()
	}
	
	private let updater = PassthroughSubject<Void, Never>()
	
	public var products: [IAPProduct] {
		iapProducts ?? []
	}
	
	public var productsPublisher: AnyPublisher<IdentifiedArrayOf<IAPProduct>, Error> {
		updater
			.compactMap { self.iapProducts }
			.mapError { _ in ProductNotFound() }
			.merge(
				with: Publishers.Async {
					try await self.fetchIfNeeded()
				}
			)
			.eraseToAnyPublisher()
	}
	
	public func buy(_ id: String) async throws {
		if isPreview {
			try await Task.sleep(nanoseconds: 1_000_000_000)
			purchases[id, default: []].append(
				IAPPurchase(
					id: UInt64.random(in: 1 ... UInt64.max),
					date: Date(),
					invalidationDate: nil
				)
			)
			updater.send()
			return
		}
		
		let product: Product
		do {
			product = try await Product.products(for: [id]).first.unwrap(ProductNotFound())
		} catch {
			// analytics.send(buyResultEvent(for: id, .error))
			throw error
		}
		
		listenForTransactions()
		// analytics.send(buySheetOpenEvent(for: id))
		let result: Product.PurchaseResult
		do {
			result = try await product.purchase()
		} catch {
			// analytics.send(buyResultEvent(for: id, .error))
			throw error
		}
		
		switch result {
		case let .success(.verified(transaction)):
			await update(with: .verified(transaction), id: id)
			// analytics.send(buyResultEvent(for: id, .success))
			if isDevelopBuild {
				debugPurchases[id] = true
			}
			updateProducts()
			await transaction.finish()
			
		case let .success(.unverified(transaction, result)):
			// analytics.send(buyResultEvent(for: id, .error))
			await transaction.finish()
			throw FailedVerification()
			
		case .pending:
			// analytics.send(buyResultEvent(for: id, .pending))
			break
			
		case .userCancelled:
			// analytics.send(buyResultEvent(for: id, .cancelled))
			throw CancellationError()
			
		@unknown default:
			break
		}
	}

	public func restore() async throws {
		guard !isPreview else {
			try await Task.sleep(nanoseconds: 1_000_000_000)
			return
		}
		try await AppStore.sync()
		await synchronize()
	}

	public func listenForTransactions() {
		guard transactionsListener == nil, !isPreview else {
			return
		}

		transactionsListener = Task(priority: .background) { [weak self] in
			// Iterate through any transactions that don't come from a direct call to `purchase()`.
			for await result in Transaction.updates {
				guard let self, !Task.isCancelled else { return }
				
				// Always finish a transaction.
				switch result {
				case let .verified(transaction):
					if !activeProducts.contains(transaction.productID) {
						// analytics.send(buyResultEvent(for: transaction.productID, .delayed_success))
					}
					
					// Deliver products to the user.
					await update(with: result, id: transaction.productID)
					await transaction.finish()
					updateProducts()
					
				case let .unverified(transaction, _):
					// analytics.send(buyResultEvent(for: transaction.productID, .delayed_error))
					await transaction.finish()
				}
			}
		}
	}

	@discardableResult
	public func fetchIfNeeded() async throws -> IdentifiedArrayOf<IAPProduct> {
		if let products = iapProducts {
			return products
		}
		return try await fetch()
	}

	@discardableResult
	public func fetch() async throws -> IdentifiedArrayOf<IAPProduct> {
		let ids = productsIDs()
		
		guard !isPreview else {
			let products = IdentifiedArrayOf<IAPProduct>(
				uniqueElements: ids.map { id in
					IAPProduct.mock(id: id)
				}
			)
			iapProducts = products
			updater.send()
			return products
		}
		
		let products = try await Product.products(for: ids)
		
		let productsMap = IdentifiedArrayOf(
			products.map {
				IAPProduct(
					$0,
					isActive: activeProducts.contains($0.id),
					purchases: purchases[$0.id] ?? []
				)
			}
		) { _, new in new }
		
		iapProducts = productsMap
		
		for product in products {
			await update(with: product.latestTransaction, id: product.id)
		}
		updateProducts()
		return iapProducts ?? []
	}
	
	public func configure(productsIDs: Set<String>) {
		configure {
			productsIDs
		}
	}

	public func configure(
		productsIDs: @escaping @Sendable () -> Set<String>
	) {
		self.productsIDs = productsIDs
	}

	public func synchronize() async {
		let start = Date()
		let all = await Transaction.all.reduce(into: [Transaction]()) { array, result in
			if let transaction = result.verified {
				array.append(transaction)
			}
		}.sorted { first, second in
			first.purchaseDate < second.purchaseDate
		}

		var states: [String: Any] = [:]
		for transaction in all {
			if let option = options[transaction.productID] {
				var state = states[transaction.productID] ?? option.stateBeforePurchase
				option.buy(transaction, &state)
				states[transaction.productID] = state
			}
		}
		for (productID, state) in states {
			if let option = options[productID] {
				option.check(Date(), &states[productID, default: option.stateBeforePurchase])
			}
		}

		let duration = Date().timeIntervalSince(start)
	
		updateProducts()
	}

	private func updatePurchasedProducts() async {
		for id in productsIDs() {
			await update(with: Transaction.latest(for: id), id: id)
		}
		
		//		let all = await Transaction.all.reduce(into: [Transaction]()) {
		//			if let transaction = $1.verified, isValid(transaction.productID, transaction.purchaseDate).0 { $0.append(transaction) }
		//		}
		
		updateProducts()
	}
	
	private func update(with result: VerificationResult<Transaction>?, id: Product.ID) async {
		guard let verificationResult = result else {
			return
		}
		
		guard case let .verified(transaction) = verificationResult else {
			return
		}
		
		let (isValidTransaction, invalidationDate) = isValid(id, transaction.purchaseDate)
		
		if transaction.isExpired || !isValidTransaction {
			purchases[id, default: []].remove(id: transaction.id)
			if boughtPurchases.value.contains(id) {
				boughtPurchases.value.remove(id)
			}
		} else {
			purchases[id, default: []][id: transaction.id] = IAPPurchase(
				id: transaction.id,
				date: transaction.purchaseDate,
				invalidationDate: [transaction.revocationDate, transaction.expirationDate, invalidationDate].compactMap(\.self).min()
			)
		}
	}
	
	private func updateProducts() {
		if var products = iapProducts {
			let activeProducts = activeProducts
			let purchases = purchases
			for i in products.indices {
				products[i].isActive = activeProducts.contains(products[i].id)
				products[i].purchases = purchases[products[i].id] ?? []
			}
			iapProducts = products
		}
		if Thread.isMainThread {
			updater.send()
		} else {
			DispatchQueue.main.async {
				self.updater.send()
			}
		}
	}
}

struct ProductDescription {

	var cacheKey: String
	var purchaseOptions: [
		String: PurchaseOption
	]
}

struct ProductCache {

	var lastModifiedDate: Date
	var state: String
}

public enum PurchaseResult: String, Hashable, Sendable, CaseIterable {

	case success
	case cancelled
	case error
	case pending
	case delayed_success
	case delayed_error
}

public struct IAPPrice: CustomStringConvertible, Hashable, Codable, Sendable {

	public let value: Decimal
	public let locale: Locale
	public let description: String

	public init(_ value: Decimal, locale: Locale = .autoupdatingCurrent, description: String? = nil) {
		self.value = value
		self.locale = locale
		self.description = description ?? Self.amountFormatter.string(from: value as NSDecimalNumber) ?? "\(value)"
	}

	public init(product: Product) {
		value = product.price
		locale = product.priceFormatStyle.locale
		description = product.displayPrice
	}

	private static let amountFormatter: NumberFormatter = {
		let formatter = NumberFormatter()
		formatter.minimumFractionDigits = 0
		formatter.maximumFractionDigits = 2
		formatter.numberStyle = .currencyISOCode
		return formatter
	}()
}

public struct IAPPurchase: Identifiable, Equatable, Codable, Sendable {

	public var id: UInt64
	public var date: Date

	public init(
		id: UInt64,
		date: Date
	) {
		self.id = id
		self.date = date
	}
}

private struct FailedVerification: Error {}
private struct ProductNotFound: Error {}
