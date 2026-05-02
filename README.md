# SwiftyWizard

SwiftyWizard is a Swift Package Manager framework for rendering simple SwiftUI wizard flows from a YAML definition.

The package currently includes:

- `SwiftyWizardView`, a SwiftUI view that renders wizard `ask` steps.
- `SwiftyWizard.runWizard(...)`, an async macOS helper that presents the wizard modally or as a sheet.
- `SwiftyWizardDemo`, a small macOS demo app.

## Requirements

- Swift 5.9+
- macOS 13+ for the demo and modal runner
- iOS 16+ for the framework target

## Installation

Add SwiftyWizard to your package dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/your-org/SwiftyWizard.git", from: "0.1.0")
]
```

Then add the product to your target:

```swift
.product(name: "SwiftyWizard", package: "SwiftyWizard")
```

## Quick Start

Use `SwiftyWizardView` directly when you want to embed a wizard in your own SwiftUI hierarchy:

```swift
import SwiftUI
import SwiftyWizard

struct ContentView: View {
    @State private var output: [String: Any?] = [:]

    var body: some View {
        SwiftyWizardView(
            wizardDef: wizardDef,
            resources: [:],
            output: $output
        )
    }
}
```

On macOS, use `runWizard` to present the wizard and await the collected output:

```swift
let output = await SwiftyWizard.runWizard(
    wizardDef: wizardDef,
    resources: resources,
    size: CGSize(width: 500, height: 350),
    view: hostView
)
```

If `view` is provided, the wizard is shown as a sheet on that view's window. Otherwise, it is shown as a borderless modal window.

## YAML Shape

SwiftyWizard currently renders `ask` steps from the `steps` list:

```yaml
wizard:
  exitButton: exit

  steps:
    - ask:
        title: Create Project
        headerImage: headerImage.png
        background: background.png
        backgroundAlpha: 30%
        cancelButtonText: Cancel
        nextButtonText: Next
        questions:
          - variable: project_name
            prompt: What is the name of your project?
            help: This is the executable name.
            type: string
            required: true
            default: My Great App
```

Question answers are written to the output dictionary using each question's `variable` value as the key.

## Supported Question Types

- `string`
- `number`
- `decimal`
- `money`
- `date`
- `boolean`
- `directory`
- `file`
- `image file`

## Templates

Text can reference values with double braces:

```yaml
prompt: Where should we create your {{project_name}} project?
```

Template lookup checks:

1. The wizard output dictionary.
2. The resources dictionary.
3. If unresolved, the placeholder is left visible with a capitalized key, such as `{{Project_Name}}`.

## Resources

The `resources` dictionary can provide named values and images. Image resources are keyed by filename in the demo:

```swift
resources["headerImage.png"] = NSImage(...)
resources["background.png"] = NSImage(...)
resources["current_year"] = 2026
```

The renderer currently uses image resources for:

- `headerImage`
- `background`

## Demo

Run the demo app with:

```sh
swift run SwiftyWizardDemo
```

The demo opens a macOS window with a button that launches the wizard as a sheet, then renders the YAML `do` steps with returned values substituted.

## Build

```sh
swift build
```

## Status

SwiftyWizard is early-stage. The current YAML parser intentionally supports only the subset needed by the renderer and demo. Unknown fields are ignored so future execution code can consume them separately.

## License

SwiftyWizard is available under the MIT License. See [LICENSE](LICENSE).
