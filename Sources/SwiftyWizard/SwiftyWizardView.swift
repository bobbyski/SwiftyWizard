import SwiftUI
import UniformTypeIdentifiers

/// The button used to leave a wizard.
public enum SwiftyWizardExitButton: String {
    /// The user completed the wizard.
    case done = "DONE"

    /// The user canceled the wizard.
    case cancel = "CANCEL"
}

/// A SwiftUI view that renders `ask` steps from a SwiftyWizard YAML definition.
public struct SwiftyWizardView: View {
    /// YAML text describing the wizard.
    public let wizardDef: String

    /// Named values or assets available to the wizard while rendering.
    public let resources: [String: Any?]

    /// Collected answers keyed by each question's `variable` value.
    @Binding public var output: [String: Any?]

    @State private var currentStepIndex = 0
    @State private var filePickerRequest: WizardFilePickerRequest?
    @State private var isFilePickerPresented = false

    private let wizard: WizardDefinition
    private let onExit: ([String: Any?]) -> Void

    /// Creates a wizard view from YAML text and caller-owned output state.
    ///
    /// - Parameters:
    ///   - wizardDef: YAML text describing the wizard.
    ///   - resources: Named values and assets, such as images, referenced by the wizard.
    ///   - output: A binding to the collected wizard answers.
    ///   - onExit: Called with `output` when the user presses Cancel or Done.
    public init(
        wizardDef: String,
        resources: [String: Any?],
        output: Binding<[String: Any?]>,
        onExit: @escaping ([String: Any?]) -> Void = { _ in }
    ) {
        self.wizardDef = wizardDef
        self.resources = resources
        self._output = output
        self.wizard = WizardDefinitionParser.parse(wizardDef)
        self.onExit = onExit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if wizard.askSteps.isEmpty {
                emptyState
            } else {
                currentPanel
                buttonBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: applyDefaults)
        .fileImporter(
            isPresented: $isFilePickerPresented,
            allowedContentTypes: filePickerRequest?.allowedTypes ?? [.item],
            allowsMultipleSelection: false,
            onCompletion: handleFilePickerResult
        )
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "wand.and.sparkles")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No ask steps found")
                .font(.headline)
            Text("Add at least one ask step to the wizard definition.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var currentPanel: some View {
        let step = wizard.askSteps[currentStepIndex]

        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                if let image = imageResource(named: step.headerImage) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                }

                Text(renderTemplate(step.title))
                    .font(.title.bold())
            }
            .padding([.top, .horizontal], 24)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(step.questions) { question in
                        questionView(for: question)
                    }
                }
                .padding(.vertical, 24)
                .padding(.horizontal, 40)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            stepBackground(for: step)
        }
    }

    @ViewBuilder
    private func stepBackground(for step: WizardAskStep) -> some View {
        if let image = imageResource(named: step.background) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .opacity(step.backgroundAlpha)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
    }

    private var buttonBar: some View {
        let step = wizard.askSteps[currentStepIndex]

        return HStack(spacing: 10) {
            Spacer()

            Button(renderTemplate(step.cancelButtonText ?? "Cancel"), action: cancel)

            if currentStepIndex > 0 {
                Button(renderTemplate(step.backButtonText ?? "Back"), action: back)
            }

            if currentStepIndex < wizard.askSteps.count - 1 {
                Button(renderTemplate(step.nextButtonText ?? "Next"), action: next)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canLeaveCurrentStep)
            } else {
                Button(renderTemplate(step.doneButtonText ?? "Done"), action: done)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canLeaveCurrentStep)
            }
        }
        .padding(16)
        .background(.bar)
    }

    @ViewBuilder
    private func questionView(for question: WizardQuestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(renderTemplate(question.prompt))
                .font(.headline)

            inputView(for: question)

            if let help = question.help, !help.isEmpty {
                Text(renderTemplate(help))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func inputView(for question: WizardQuestion) -> some View {
        switch question.type {
        case .boolean:
            Toggle(
                "Enabled",
                isOn: boolBinding(for: question.variable)
            )
            .labelsHidden()

        case .date:
            DatePicker(
                "",
                selection: dateBinding(for: question.variable),
                displayedComponents: [.date]
            )
            .labelsHidden()

        case .choice:
            Picker("", selection: stringBinding(for: question.variable)) {
                ForEach(question.options) { option in
                    Text(renderTemplate(option.label)).tag(option.value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

        case .directory, .file, .imageFile:
            HStack(spacing: 8) {
                TextField("", text: stringBinding(for: question.variable))
                    .textFieldStyle(.roundedBorder)

                Button("Choose") {
                    filePickerRequest = WizardFilePickerRequest(
                        variable: question.variable,
                        allowedTypes: question.type.allowedContentTypes
                    )
                    isFilePickerPresented = true
                }
            }

        case .number, .decimal, .money, .string:
            TextField("", text: textBinding(for: question))
                .textFieldStyle(.roundedBorder)
        }
    }

    private var canLeaveCurrentStep: Bool {
        let step = wizard.askSteps[currentStepIndex]

        return step.questions.allSatisfy { question in
            guard question.required else {
                return true
            }

            switch output[question.variable] ?? nil {
            case let value as String:
                return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .some:
                return true
            case .none:
                return false
            }
        }
    }

    private func stringBinding(for variable: String) -> Binding<String> {
        Binding(
            get: {
                switch output[variable] ?? nil {
                case let value as String:
                    return value
                case let value as Int:
                    return String(value)
                case let value as Double:
                    return String(value)
                case let value as Decimal:
                    return "\(value)"
                case .some(let value):
                    return String(describing: value)
                case .none:
                    return ""
                }
            },
            set: { newValue in
                output[variable] = newValue
            }
        )
    }

    private func textBinding(for question: WizardQuestion) -> Binding<String> {
        Binding(
            get: {
                stringValue(for: question.variable)
            },
            set: { newValue in
                switch question.type {
                case .number:
                    if let value = Int(newValue) {
                        output[question.variable] = value
                    } else {
                        output[question.variable] = newValue
                    }
                case .decimal, .money:
                    if let value = Decimal(string: newValue) {
                        output[question.variable] = value
                    } else {
                        output[question.variable] = newValue
                    }
                default:
                    output[question.variable] = newValue
                }
            }
        )
    }

    private func stringValue(for variable: String) -> String {
        switch output[variable] ?? nil {
        case let value as String:
            return value
        case let value as Int:
            return String(value)
        case let value as Double:
            return String(value)
        case let value as Decimal:
            return "\(value)"
        case .some(let value):
            return String(describing: value)
        case .none:
            return ""
        }
    }

    private func boolBinding(for variable: String) -> Binding<Bool> {
        Binding(
            get: {
                switch output[variable] ?? nil {
                case let value as Bool:
                    return value
                case let value as String:
                    return ["true", "yes", "1"].contains(value.lowercased())
                default:
                    return false
                }
            },
            set: { newValue in
                output[variable] = newValue
            }
        )
    }

    private func dateBinding(for variable: String) -> Binding<Date> {
        Binding(
            get: {
                if let value = output[variable] ?? nil, let date = value as? Date {
                    return date
                }
                return Date()
            },
            set: { newValue in
                output[variable] = newValue
            }
        )
    }

    private func applyDefaults() {
        for step in wizard.askSteps {
            for question in step.questions where output[question.variable] == nil {
                // Defaults are written once so user edits are never overwritten during redraws.
                if let value = question.defaultValue as? String {
                    output[question.variable] = renderTemplate(value)
                } else {
                    output[question.variable] = question.defaultValue
                }
            }
        }
    }

    private func cancel() {
        setExitButton(.cancel)
        onExit(output)
        currentStepIndex = 0
    }

    private func back() {
        currentStepIndex = max(0, currentStepIndex - 1)
    }

    private func next() {
        guard canLeaveCurrentStep else {
            return
        }
        currentStepIndex = min(wizard.askSteps.count - 1, currentStepIndex + 1)
    }

    private func done() {
        guard canLeaveCurrentStep else {
            return
        }
        setExitButton(.done)
        onExit(output)
    }

    private func setExitButton(_ exitButton: SwiftyWizardExitButton) {
        guard let variable = wizard.exitButtonVariable, !variable.isEmpty else {
            return
        }

        output[variable] = exitButton.rawValue
    }

    private func handleFilePickerResult(_ result: Result<[URL], Error>) {
        guard let request = filePickerRequest else {
            return
        }

        if case .success(let urls) = result, let url = urls.first {
            output[request.variable] = url.path
        }

        filePickerRequest = nil
    }

    private func renderTemplate(_ text: String) -> String {
        var rendered = ""
        var remainder = text[...]

        // Unresolved placeholders stay visible in the UI with their braces intact.
        while let startRange = remainder.range(of: "{{") {
            rendered += remainder[..<startRange.lowerBound]

            let afterStart = remainder[startRange.upperBound...]
            guard let endRange = afterStart.range(of: "}}") else {
                rendered += remainder[startRange.lowerBound...]
                return rendered
            }

            let key = String(afterStart[..<endRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            rendered += templateValue(for: key) ?? "{{\(key.capitalized)}}"
            remainder = afterStart[endRange.upperBound...]
        }

        rendered += remainder
        return rendered
    }

    private func templateValue(for key: String) -> String? {
        if let outputValue = output[key] ?? nil {
            return String(describing: outputValue)
        }

        if let resourceValue = resources[key] ?? nil {
            return String(describing: resourceValue)
        }

        return nil
    }

    private func imageResource(named name: String?) -> NSImage? {
        guard let name, let value = resources[name] ?? nil else {
            return nil
        }

        return value as? NSImage
    }
}

