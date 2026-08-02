import ActiveUI
import AppKit
import Foundation
import SwiftyWizard
import UniformTypeIdentifiers

/// The wizard, drawn with ActiveUI.
///
/// **F9's point, and the rewrite rule's clearest test.** `SwiftyWizard` shipped
/// as a single 774-line SwiftUI view that contained the schema, the YAML
/// parser, validation, navigation and templating along with the drawing. None
/// of that was about SwiftUI; it was simply where the wizard had been written.
///
/// Extracting `WizardEngine` made this file possible, and this file is what
/// proves the extraction was real: **it renders the same wizards, from the same
/// YAML, with no parser and no rules of its own.** Had a rule been left behind
/// in the SwiftUI view, it would be missing here — and the two wizards would
/// disagree the first time anyone changed one of them.
///
///     let wizard = AUIWizard(yaml: definition, resources: resources)
///     wizard.onFinish = { answers in … }      // nil means cancelled
///     window.contentView = wizard.makeRootView().nativeView
@MainActor
public final class AUIWizard {
    private let engine: WizardEngine

    private let container = AUIStack(.vertical, spacing: 0, alignment: .fill)
    private let questionArea = AUIStack(.vertical, spacing: 14, alignment: .fill)
    private let titleLabel = AUILabel("")
    private let buttonBar = AUIStack(.horizontal, spacing: 8, alignment: .center)
    private var primaryButton: AUIButton?

    /// Called when the wizard ends: the answers on Done, `nil` on Cancel.
    ///
    /// Report, don't perform — closing a window is the host's decision, which
    /// is why this hands back values rather than dismissing anything itself.
    public var onFinish: (([String: Any?]?) -> Void)?

    /// Creates a wizard from YAML.
    public init(yaml: String, resources: [String: Any?] = [:]) {
        engine = WizardEngine(yaml: yaml, resources: resources)
        container.wraps = false
        questionArea.wraps = false
        buttonBar.wraps = false
    }

    /// The answers so far — for a host that wants them without waiting.
    public var answers: [String: Any?] { engine.answers }

    /// The wizard's view.
    public func makeRootView() -> AUIView {
        titleLabel.font = .headline

        let scroller = AUIScrollView(.vertical)
        scroller.addChild(questionArea.padding(16))
        scroller.flexibility = .both()

        container.addChild(titleLabel.padding(16))
        container.addChild(scroller.stretches())
        container.addChild(buttonBar.padding(12))
        container.minimumSize = CGSize(width: 460, height: 320)

        rebuild()
        return container
    }

    // MARK: - Rendering

    /// Rebuilds the current step.
    ///
    /// The whole step is rebuilt on navigation, because the questions change.
    /// Editing a field does **not** rebuild — the controls keep their focus and
    /// selection, which is the retained-mode advantage and the reason a caret
    /// does not jump while you type.
    private func rebuild() {
        for child in questionArea.children { child.removeFromParent() }
        for child in buttonBar.children { child.removeFromParent() }

        guard let step = engine.currentStep else {
            let empty = AUILabel("This wizard has no steps.")
            empty.themeClasses = "quiet"
            questionArea.addChild(empty)
            questionArea.invalidateLayout()
            return
        }

        titleLabel.text = engine.renderTemplate(step.title)
        titleLabel.refreshSelf()

        for question in step.questions {
            questionArea.addChild(makeQuestion(question))
        }
        questionArea.invalidateLayout()
        buildButtonBar(step)
    }

    private func makeQuestion(_ question: WizardQuestion) -> AUIView {
        // Prompts and help are templated, so `{{project_name}}` in a later
        // step's prompt shows what the user typed earlier.
        let prompt = AUILabel(engine.renderTemplate(question.prompt))
        if question.required {
            prompt.tooltip = "Required"
        }

        let column = AUIStack(.vertical, spacing: 4, alignment: .fill)
        column.wraps = false
        column.addChild(prompt)
        column.addChild(makeInput(question))

        if let help = question.help, !help.isEmpty {
            let helpLabel = AUILabel(engine.renderTemplate(help))
            helpLabel.themeClasses = "quiet"
            helpLabel.font = .caption
            column.addChild(helpLabel)
        }
        return column
    }

    private func makeInput(_ question: WizardQuestion) -> AUIView {
        switch question.type {
        case .boolean:
            let toggle = AUIToggle("")
            toggle.isOn = engine.boolValue(for: question.variable)
            toggle.onChange = { [weak self] (isOn: Bool) in
                self?.engine.setValue(isOn, for: question.variable)
                self?.refreshButtons()
            }
            return toggle

        case .choice:
            let picker = AUIPicker(question.options.map(\.label))
            if let index = question.options.firstIndex(where: {
                $0.value == engine.stringValue(for: question.variable)
            }) {
                picker.selectedIndex = index
            }
            picker.onSelectionChange = { [weak self] (index: Int) in
                guard let self, question.options.indices.contains(index) else { return }
                self.engine.setValue(question.options[index].value, for: question.variable)
                self.refreshButtons()
            }
            return picker

        case .date:
            let picker = AUIDatePicker()
            picker.date = engine.dateValue(for: question.variable)
            picker.onChange = { [weak self] (date: Date) in
                self?.engine.setValue(date, for: question.variable)
                self?.refreshButtons()
            }
            return picker

        case .directory, .file, .imageFile:
            return makeFilePicker(question)

        case .string, .number, .decimal, .money:
            let field = AUITextField(engine.stringValue(for: question.variable))
            field.onChange = { [weak self] text in
                // `setText` coerces to the question's type and keeps half-typed
                // input as text rather than rejecting it mid-keystroke.
                self?.engine.setText(text, for: question)
                self?.refreshButtons()
            }
            return field
        }
    }

    /// A path field with a Choose… button.
    ///
    /// The engine deliberately knows nothing about `NSOpenPanel`: picking a file
    /// is a host capability, and on Windows or Linux it is a different panel
    /// entirely. The engine is told the *result*, which is the same split that
    /// let this wrapper exist at all.
    private func makeFilePicker(_ question: WizardQuestion) -> AUIView {
        let field = AUITextField(engine.stringValue(for: question.variable))
        field.onChange = { [weak self] text in
            self?.engine.setValue(text, for: question.variable)
            self?.refreshButtons()
        }

        let choose = AUIButton("Choose…") { [weak self] in
            guard let self else { return }
            let panel = NSOpenPanel()
            panel.canChooseDirectories = question.type == .directory
            panel.canChooseFiles = question.type != .directory
            panel.allowsMultipleSelection = false
            panel.allowedContentTypes = question.type.allowedContentTypes
            guard panel.runModal() == .OK, let url = panel.url else { return }
            self.engine.setValue(url.path, for: question.variable)
            field.text = url.path
            self.refreshButtons()
        }

        let row = AUIStack(.horizontal, spacing: 6, alignment: .center)
        row.wraps = false
        row.addChild(field.stretches())
        row.addChild(choose)
        return row
    }

    // MARK: - Buttons

    private func buildButtonBar(_ step: WizardAskStep) {
        let cancel = AUIButton(step.cancelButtonText ?? "Cancel") { [weak self] in
            guard let self else { return }
            // Cancel never validates — leaving is always allowed.
            self.onFinish?(self.engine.finish(.cancel))
        }
        buttonBar.addChild(cancel)
        buttonBar.addChild(AUISpacer())

        if engine.canGoBack {
            buttonBar.addChild(AUIButton(step.backButtonText ?? "Back") { [weak self] in
                self?.engine.back()
                self?.rebuild()
            })
        }

        let isLast = engine.isLastStep
        let primary = AUIButton(
            isLast ? (step.doneButtonText ?? "Done") : (step.nextButtonText ?? "Next")
        ) { [weak self] in
            guard let self else { return }
            if isLast {
                // `finish` returns nil on an unsatisfied step, so a host cannot
                // close a wizard the engine would not let you leave.
                if let answers = self.engine.finish(.done) {
                    self.onFinish?(answers)
                }
            } else if self.engine.next() {
                self.rebuild()
            }
        }
        primaryButton = primary
        buttonBar.addChild(primary)
        refreshButtons()
        buttonBar.invalidateLayout()
    }

    /// Enables the primary button from the engine's validation.
    ///
    /// Called on every edit — cheap, and it means a required field enables the
    /// button the moment it is satisfied rather than on the next navigation.
    private func refreshButtons() {
        primaryButton?.isEnabled = engine.canLeaveCurrentStep
    }
}
