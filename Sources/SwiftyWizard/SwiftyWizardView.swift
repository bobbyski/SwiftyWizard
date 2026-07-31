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
    @State private var filePickerRequest: FilePickerRequest?
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
                    filePickerRequest = FilePickerRequest(
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

/// Transient file-picker state for a file, directory, or image question.
private struct FilePickerRequest {
    var variable: String
    var allowedTypes: [UTType]
}

/// Parsed wizard data used by the renderer.
private struct WizardDefinition {
    var name: String
    var exitButtonVariable: String?
    var askSteps: [WizardAskStep]
}

/// One rendered panel in the wizard.
private struct WizardAskStep: Identifiable {
    let id = UUID()
    var title: String
    var background: String?
    var backgroundAlpha: Double
    var headerImage: String?
    var cancelButtonText: String?
    var backButtonText: String?
    var nextButtonText: String?
    var doneButtonText: String?
    var questions: [WizardQuestion]
}

/// One input element inside an `ask` step.
private struct WizardQuestion: Identifiable {
    var id: String { variable }
    var variable: String
    var prompt: String
    var help: String?
    var type: WizardQuestionType
    var required: Bool
    var defaultValue: Any?
    var options: [WizardQuestionOption]
}

/// One selectable value inside a choice question.
private struct WizardQuestionOption: Identifiable {
    var id: String { value }
    var value: String
    var label: String
}

/// Supported question input types.
private enum WizardQuestionType: String {
    case string
    case number
    case decimal
    case money
    case date
    case boolean
    case choice
    case directory
    case file
    case imageFile

    init(rawValue: String) {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "number", "int", "integer":
            self = .number
        case "decimal", "double", "float":
            self = .decimal
        case "money", "currency":
            self = .money
        case "date":
            self = .date
        case "boolean", "bool":
            self = .boolean
        case "choice", "select", "popup", "picker", "menu":
            self = .choice
        case "directory", "folder":
            self = .directory
        case "file":
            self = .file
        case "image", "image_file", "image file", "imagefile":
            self = .imageFile
        default:
            self = .string
        }
    }

    var allowedContentTypes: [UTType] {
        switch self {
        case .directory:
            return [.folder]
        case .imageFile:
            return [.image]
        case .file:
            return [.item]
        default:
            return [.item]
        }
    }
}

/// Minimal YAML parser for the SwiftyWizard demo schema.
///
/// This intentionally parses only the subset currently used by the renderer. Fields for other
/// parts of the system can remain in the YAML and are ignored until the framework supports them.
private enum WizardDefinitionParser {
    static func parse(_ yaml: String) -> WizardDefinition {
        let lines = yaml
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { ParsedLine(raw: String($0)) }

        return WizardDefinition(
            name: parseWizardName(from: lines),
            exitButtonVariable: parseExitButtonVariable(from: lines),
            askSteps: parseAskSteps(from: lines)
        )
    }

    private static func parseWizardName(from lines: [ParsedLine]) -> String {
        for line in lines where line.text.hasPrefix("name:") {
            return value(after: "name:", in: line.text)
        }

        return "Wizard"
    }

    private static func parseExitButtonVariable(from lines: [ParsedLine]) -> String? {
        for line in lines where line.text.hasPrefix("exitButton:") {
            return value(after: "exitButton:", in: line.text)
        }

        return nil
    }

    private static func parseAskSteps(from lines: [ParsedLine]) -> [WizardAskStep] {
        var steps: [WizardAskStep] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]

            guard line.text == "- ask:" else {
                index += 1
                continue
            }

            let stepStart = index
            index += 1

            // Capture all indented lines until the next sibling YAML list item.
            while index < lines.count {
                let nextLine = lines[index]
                if nextLine.indent == line.indent && nextLine.text.hasPrefix("- ") {
                    break
                }
                index += 1
            }

            let block = Array(lines[stepStart..<index])
            steps.append(parseAskStep(from: block))
        }

        return steps
    }

    private static func parseAskStep(from lines: [ParsedLine]) -> WizardAskStep {
        var title = "Step"
        var background: String?
        var backgroundAlpha = 1.0
        var headerImage: String?
        var cancelButtonText: String?
        var backButtonText: String?
        var nextButtonText: String?
        var doneButtonText: String?
        var questions: [WizardQuestion] = []
        var questionStartIndexes: [Int] = []

        for (index, line) in lines.enumerated() {
            if line.text.hasPrefix("title:") && questions.isEmpty {
                title = value(after: "title:", in: line.text)
            } else if line.text.hasPrefix("background:") {
                background = value(after: "background:", in: line.text)
            } else if line.text.hasPrefix("backgroundAlpha:") {
                backgroundAlpha = alphaValue(value(after: "backgroundAlpha:", in: line.text))
            } else if line.text.hasPrefix("headerImage:") {
                headerImage = value(after: "headerImage:", in: line.text)
            } else if line.text.hasPrefix("icon:") {
                headerImage = value(after: "icon:", in: line.text)
            } else if line.text.hasPrefix("cancelButtonText:") {
                cancelButtonText = value(after: "cancelButtonText:", in: line.text)
            } else if line.text.hasPrefix("backButtonText:") {
                backButtonText = value(after: "backButtonText:", in: line.text)
            } else if line.text.hasPrefix("nextButtonText:") {
                nextButtonText = value(after: "nextButtonText:", in: line.text)
            } else if line.text.hasPrefix("doneButtonText:") {
                doneButtonText = value(after: "doneButtonText:", in: line.text)
            }

            if line.text.hasPrefix("- variable:") {
                questionStartIndexes.append(index)
            }
        }

        for (offset, startIndex) in questionStartIndexes.enumerated() {
            let endIndex = offset + 1 < questionStartIndexes.count ? questionStartIndexes[offset + 1] : lines.count
            questions.append(parseQuestion(from: Array(lines[startIndex..<endIndex])))
        }

        return WizardAskStep(
            title: title,
            background: background,
            backgroundAlpha: backgroundAlpha,
            headerImage: headerImage,
            cancelButtonText: cancelButtonText,
            backButtonText: backButtonText,
            nextButtonText: nextButtonText,
            doneButtonText: doneButtonText,
            questions: questions
        )
    }

    private static func parseQuestion(from lines: [ParsedLine]) -> WizardQuestion {
        var variable = ""
        var prompt = ""
        var help: String?
        var type = WizardQuestionType.string
        var required = false
        var defaultText: String?
        var options: [WizardQuestionOption] = []

        for (index, line) in lines.enumerated() {
            if line.text.hasPrefix("- variable:") {
                variable = value(after: "- variable:", in: line.text)
            } else if line.text.hasPrefix("prompt:") {
                prompt = value(after: "prompt:", in: line.text)
            } else if line.text.hasPrefix("help:") {
                help = value(after: "help:", in: line.text)
            } else if line.text.hasPrefix("type:") {
                type = WizardQuestionType(rawValue: value(after: "type:", in: line.text))
            } else if line.text.hasPrefix("required:") {
                required = boolValue(value(after: "required:", in: line.text))
            } else if line.text.hasPrefix("default:") {
                defaultText = value(after: "default:", in: line.text)
            } else if line.text.hasPrefix("- value:") {
                let optionValue = value(after: "- value:", in: line.text)
                let optionLabel = optionLabel(after: index, in: lines) ?? optionValue
                options.append(WizardQuestionOption(value: optionValue, label: optionLabel))
            }
        }

        if prompt.isEmpty {
            prompt = variable
        }

        return WizardQuestion(
            variable: variable,
            prompt: prompt,
            help: help,
            type: type,
            required: required,
            defaultValue: defaultValue(from: defaultText, type: type, options: options),
            options: options
        )
    }

    private static func defaultValue(from text: String?, type: WizardQuestionType, options: [WizardQuestionOption] = []) -> Any? {
        guard let text else {
            return type == .choice ? options.first?.value : nil
        }

        switch type {
        case .number:
            return Int(text) ?? text
        case .decimal, .money:
            return Decimal(string: text) ?? text
        case .boolean:
            return boolValue(text)
        default:
            return text
        }
    }

    private static func optionLabel(after index: Int, in lines: [ParsedLine]) -> String? {
        guard index + 1 < lines.count else {
            return nil
        }

        let next = lines[index + 1]
        guard next.text.hasPrefix("label:") else {
            return nil
        }

        return value(after: "label:", in: next.text)
    }

    private static func value(after prefix: String, in text: String) -> String {
        let rawValue = text.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)

        // Strip simple quoted scalars used in the demo YAML.
        if rawValue.hasPrefix("\""), rawValue.hasSuffix("\""), rawValue.count >= 2 {
            return String(rawValue.dropFirst().dropLast())
        }

        return rawValue
    }

    private static func boolValue(_ value: String) -> Bool {
        ["true", "yes", "1"].contains(value.lowercased())
    }

    private static func alphaValue(_ value: String) -> Double {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasSuffix("%") {
            let percent = trimmed.dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
            return clampedAlpha((Double(percent) ?? 100) / 100)
        }

        return clampedAlpha(Double(trimmed) ?? 1)
    }

    private static func clampedAlpha(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

/// A YAML line with indentation metadata for simple block parsing.
private struct ParsedLine {
    var indent: Int
    var text: String

    init(raw: String) {
        self.indent = raw.prefix { $0 == " " }.count
        self.text = raw.trimmingCharacters(in: .whitespaces)
    }
}
