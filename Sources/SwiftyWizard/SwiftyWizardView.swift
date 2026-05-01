import SwiftUI

public struct SwiftyWizardView: View {
    public let wizardDef: String
    public let resources: [String: Any?]
    @Binding public var output: [String: Any?]

    public init(
        wizardDef: String,
        resources: [String: Any?],
        output: Binding<[String: Any?]>
    ) {
        self.wizardDef = wizardDef
        self.resources = resources
        self._output = output
    }

    public var body: some View {
        Label("Hello world", systemImage: "sparkles")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
