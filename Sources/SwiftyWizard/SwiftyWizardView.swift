import SwiftUI

public struct SwiftyWizardView: View {
    public init() {}

    public var body: some View {
        Label("Hello world", systemImage: "sparkles")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
