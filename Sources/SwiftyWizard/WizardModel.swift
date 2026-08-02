import Foundation
import UniformTypeIdentifiers

// The wizard's model and YAML parser.
//
// **This was `private` inside `SwiftyWizardView`** — a 774-line SwiftUI struct
// that also contained the definition types, the parser, validation, navigation
// and templating. None of it imports SwiftUI or draws anything: it is the
// wizard *engine*, and it was only in a view because that is where it was first
// written.
//
// Moved out so a second UI framework can render the same wizard rather than
// reimplementing the schema. That is the rewrite rule this project applies
// everywhere else: an AppKit/Foundation core with wrappers over it, never two
// parallel implementations that agree until one is fixed.

/// Transient file-picker state for a file, directory, or image question.
public struct WizardFilePickerRequest {
    public var variable: String
    public var allowedTypes: [UTType]
}

/// Parsed wizard data used by the renderer.
public struct WizardDefinition {
    public var name: String
    public var exitButtonVariable: String?
    public var askSteps: [WizardAskStep]
}

/// One rendered panel in the wizard.
public struct WizardAskStep: Identifiable {
    public let id = UUID()
    public var title: String
    public var background: String?
    public var backgroundAlpha: Double
    public var headerImage: String?
    public var cancelButtonText: String?
    public var backButtonText: String?
    public var nextButtonText: String?
    public var doneButtonText: String?
    public var questions: [WizardQuestion]
}

/// One input element inside an `ask` step.
public struct WizardQuestion: Identifiable {
    public var id: String { variable }
    public var variable: String
    public var prompt: String
    public var help: String?
    public var type: WizardQuestionType
    public var required: Bool
    public var defaultValue: Any?
    public var options: [WizardQuestionOption]
}

/// One selectable value inside a choice question.
public struct WizardQuestionOption: Identifiable {
    public var id: String { value }
    public var value: String
    public var label: String
}

/// Supported question input types.
public enum WizardQuestionType: String {
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

    public init(rawValue: String) {
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

    public var allowedContentTypes: [UTType] {
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
public enum WizardDefinitionParser {
    public static func parse(_ yaml: String) -> WizardDefinition {
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
struct ParsedLine {
    public var indent: Int
    public var text: String

    init(raw: String) {
        self.indent = raw.prefix { $0 == " " }.count
        self.text = raw.trimmingCharacters(in: .whitespaces)
    }
}
