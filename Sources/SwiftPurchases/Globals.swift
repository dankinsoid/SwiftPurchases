import Foundation

#if DEBUG
let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" || ProcessInfo.processInfo.processName == "XCPreviewAgent"
#else
let isPreview = false
#endif

var isDevelopBuild: Bool {
#if DEBUG
	return true
#else
#if targetEnvironment(simulator)
	return true
#else
	return isPreview || Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
#endif
#endif
}