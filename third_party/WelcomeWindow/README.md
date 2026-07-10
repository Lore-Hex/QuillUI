<p align="center">
  <img src="https://github.com/CodeEditApp/WelcomeWindow/blob/main/.github/WelcomeWindow-Icon-128@2x.png?raw=true" height="128">
  <h1 align="center">WelcomeWindow</h1>
</p>

<p align="center">
  <a aria-label="Follow CodeEdit on X" href="https://x.com/CodeEditApp" target="_blank">
    <img alt="" src="https://img.shields.io/badge/Follow%20@CodeEditApp-black.svg?style=for-the-badge&logo=X">
  </a>
  <a aria-label="Join the community on Discord" href="https://discord.gg/vChUXVf9Em" target="_blank">
    <img alt="" src="https://img.shields.io/badge/Join%20the%20community-black.svg?style=for-the-badge&logo=Discord">
  </a>
  <a aria-label="Read the Documentation" href="https://codeeditapp.github.io/WelcomeWindow/documentation/welcomewindow/" target="_blank">
    <img alt="" src="https://img.shields.io/badge/Documentation-black.svg?style=for-the-badge&logo=readthedocs&logoColor=blue">
  </a>
</p>

A highly customizable welcome window built for macOS applications. This package supports NSDocument-based apps and offers the ability to override the recent list for other use cases. It's designed to provide a native and elegant welcome experience for your app at launch, with support for new/open document actions, drag-and-drop functionality, and dynamic layouts.

![GitHub release](https://img.shields.io/github/v/release/CodeEditApp/WelcomeWindow?color=orange&label=latest%20release&sort=semver&style=flat-square)
![Github Tests](https://img.shields.io/github/actions/workflow/status/CodeEditApp/WelcomeWindow/CI-push.yml?branch=main&label=tests&style=flat-square)
![GitHub Repo stars](https://img.shields.io/github/stars/CodeEditApp/WelcomeWindow?style=flat-square)
![GitHub forks](https://img.shields.io/github/forks/CodeEditApp/WelcomeWindow?style=flat-square)
[![Discord Badge](https://img.shields.io/discord/951544472238444645?color=5865F2&label=Discord&logo=discord&logoColor=white&style=flat-square)](https://discord.gg/vChUXVf9Em)

![Demo Image](https://github.com/user-attachments/assets/6a30bf7a-1b46-4fe1-bf84-39305d8ba85f)

## Documentation

This package is fully documented [here](https://codeeditapp.github.io/WelcomeWindow/documentation/welcomewindow/).

## Usage

To use welcome window, simply import the package

```swift
import WelcomeWindow
```

And add it as a window in your SwiftUI App.

```swift
@main
struct CodeEditApp: App {
    @Environment(\.dismiss) private var dismiss

    var body: some Scene {
        WelcomeWindow(
            // Add two action buttons below your icon
            actions: { dismiss in
                WelcomeButton(
                    iconName: "circle.fill",
                    title: "New Text Document",
                    action: {
                        NSDocumentController.shared.createFileDocumentWithDialog(
                            configuration: .init(title: "Create new text document"),
                            onCompletion: { dismiss() }
                        )
                    }
                )
                WelcomeButton(
                    iconName: "triangle.fill",
                    title: "Open Text Document or Folder",
                    action: {
                        NSDocumentController.shared.openDocumentWithDialog(
                            configuration: .init(canChooseDirectories: true),
                            onDialogPresented: { dismiss() },
                            onCancel: { openWindow(id: "welcome") }
                        )
                    }
                )
            },
            // Receive files via drag and drop
            onDrop: { url, dismiss in
                print("File dropped at: \(url.path)")

                Task {
                    NSDocumentController.shared.openDocument(at: url, onCompletion: { dismiss() })
                }
            }
        )
    }
}
```

<details><summary>Examples from real apps!</summary>

| [CodeEdit](https://github.com/CodeEditApp/CodeEdit)        | ![CodeEdit Demo Image](./.github/demos/codeedit.png)     |
| ---------------------------------------------------------- | -------------------------------------------------------- |
| [CircuitPro](https://github.com/CircuitProApp/CircuitPro/) | ![CircuitPro Demo Image](./.github/demos/circuitpro.png) |

</details>


## License

Licensed under the [MIT license](https://github.com/CodeEditApp/WelcomeWindow/blob/main/LICENSE.md)
