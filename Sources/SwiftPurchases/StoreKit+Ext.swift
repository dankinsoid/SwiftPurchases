import StoreKit

extension Transaction {

	var isExpired: Bool {
		let now = Date()
		if let date = revocationDate, date < now, date > purchaseDate {
			return true
		}
		if let expirationDate {
			return expirationDate < now
		}
		return false
	}
}

extension VerificationResult {
	
	var verified: SignedType? {
		switch self {
		case let .verified(signedType):
			return signedType
		case .unverified:
			return nil
		}
	}
}
