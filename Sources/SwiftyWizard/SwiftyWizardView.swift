import SwiftUI
import UniformTypeIdentifiers

public enum SwiftyWizardExitButton: String {
    case done = "DONE"
    case cancel = "CANCEL"
}

public struct SwiftyWizardView: View {
    public let wizardDef: String
    public let resources: [String: Any?]
    @Binding public var output: [String: Any?]

    @State private var currentStepIndex = 0
    @State private var filePickerRequest: FilePickerRequest?
    @State private var isFilePickerPresented = false

    private let wizard: WizardDefinition
    private let onExit: ([String: Any?]) -> Void

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
            VStack(alignment: .leading, spacing: 6) {
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
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

            if let help = question.help, !help.isEmpty {
                Text(renderTemplate(help))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            inputView(for: question)
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
}

private struct FilePickerRequest {
    var variable: String
    var allowedTypes: [UTType]
}

private struct WizardDefinition {
    var name: String
    var exitButtonVariable: String?
    var askSteps: [WizardAskStep]
}

private struct WizardAskStep: Identifiable {
    let id = UUID()
    var title: String
    var cancelButtonText: String?
    var backButtonText: String?
    var nextButtonText: String?
    var doneButtonText: String?
    var questions: [WizardQuestion]
}

private struct WizardQuestion: Identifiable {
    var id: String { variable }
    var variable: String
    var prompt: String
    var help: String?
    var type: WizardQuestionType
    var required: Bool
    var defaultValue: Any?
}

private enum WizardQuestionType: String {
    case string
    case number
    case decimal
    case money
    case date
    case boolean
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
        var cancelButtonText: String?
        var backButtonText: String?
        var nextButtonText: String?
        var doneButtonText: String?
        var questions: [WizardQuestion] = []
        var questionStartIndexes: [Int] = []

        for (index, line) in lines.enumerated() {
            if line.text.hasPrefix("title:") && questions.isEmpty {
                title = value(after: "title:", in: line.text)
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

        for line in lines {
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
            defaultValue: defaultValue(from: defaultText, type: type)
        )
    }

    private static func defaultValue(from text: String?, type: WizardQuestionType) -> Any? {
        guard let text else {
            return nil
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

    private static func value(after prefix: String, in text: String) -> String {
        let rawValue = text.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)

        if rawValue.hasPrefix("\""), rawValue.hasSuffix("\""), rawValue.count >= 2 {
            return String(rawValue.dropFirst().dropLast())
        }

        return rawValue
    }

    private static func boolValue(_ value: String) -> Bool {
        ["true", "yes", "1"].contains(value.lowercased())
    }
}

private struct ParsedLine {
    var indent: Int
    var text: String

    init(raw: String) {
        self.indent = raw.prefix { $0 == " " }.count
        self.text = raw.trimmingCharacters(in: .whitespaces)
    }
}
