// Swift macOS entry point
// 當 XCTest framework 不可用時，用 fallback runner

import Dispatch

func runTests() async {
    print("🧪 BridgeMobile 整合測試")
    print("---")
    testTokensCountIs85()
    testTokenRGBAValues()
    testAlphaSupport()
    await testClientInitialization()
    print("---")
    print("🎉 所有測試通過！")
    exit(0)
}

#if !canImport(XCTest)
// fallback runner via @main
@main
struct BridgeMobileTestRunner {
    static func main() {
        Task {
            await runTests()
        }
        dispatchMain()
    }
}
#endif
