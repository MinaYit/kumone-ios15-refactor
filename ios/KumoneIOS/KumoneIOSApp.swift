import Foundation
import SwiftUI
import KumoneIOSFeature

@main
struct KumoneIOSApp: App {
    private var shouldUseIOS15CompatibilityRoot: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTestingIOS15Root")
    }

    var body: some Scene {
        WindowGroup {
            if shouldUseIOS15CompatibilityRoot {
                IOS15MainWindow()
            } else if #available(iOS 16.0, *) {
                IOSMainWindow()
            } else {
                IOS15MainWindow()
            }
        }
    }
}
