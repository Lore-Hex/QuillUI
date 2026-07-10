<p align="center">
  <img src="https://github.com/CodeEditApp/AboutWindow/blob/main/.github/AboutWindow-Icon-128@2x.png?raw=true" height="128">
  <h1 align="center">AboutWindow</h1>
</p>

<p align="center">
  <a aria-label="Follow CodeEdit on X" href="https://x.com/CodeEditApp" target="_blank">
    <img alt="" src="https://img.shields.io/badge/Follow%20@CodeEditApp-black.svg?style=for-the-badge&logo=X">
  </a>
  <a aria-label="Join the community on Discord" href="https://discord.gg/vChUXVf9Em" target="_blank">
    <img alt="" src="https://img.shields.io/badge/Join%20the%20community-black.svg?style=for-the-badge&logo=Discord">
  </a>
  <a aria-label="Read the Documentation" href="https://codeeditapp.github.io/AboutWindow/documentation/aboutwindow/" target="_blank">
    <img alt="" src="https://img.shields.io/badge/Documentation-black.svg?style=for-the-badge&logo=readthedocs&logoColor=blue">
  </a>
</p>

A customizable About window for macOS applications, featuring an app icon, version info, up to three action buttons, and footer text. Supports in-window navigation to custom pages, making it easy to showcase details, acknowledgments, or licensing information in a native, polished interface.

![GitHub release](https://img.shields.io/github/v/release/CodeEditApp/AboutWindow?color=orange&label=latest%20release&sort=semver&style=flat-square)
![Github Tests](https://img.shields.io/github/actions/workflow/status/CodeEditApp/AboutWindow/CI-push.yml?branch=main&label=tests&style=flat-square)
![GitHub Repo stars](https://img.shields.io/github/stars/CodeEditApp/AboutWindow?style=flat-square)
![GitHub forks](https://img.shields.io/github/forks/CodeEditApp/AboutWindow?style=flat-square)
[![Discord Badge](https://img.shields.io/discord/951544472238444645?color=5865F2&label=Discord&logo=discord&logoColor=white&style=flat-square)](https://discord.gg/vChUXVf9Em)

<p align="center">
  <img width="830" alt="image" src="https://github.com/user-attachments/assets/de69c6dc-7615-4c9c-a422-5592f5beec94" />
</p>

## Documentation

This package is fully documented [here](https://codeeditapp.github.io/AboutWindow/documentation/aboutwindow/).

## Usage

To use `AboutWindow`, simply add it to your app.

```swift
AboutWindow(actions: {
    AboutButton(title: "Contributors", destination: {
        ContributorsView()
    })
    AboutButton(title: "Acknowledgements", destination: {
        AcknowledgementsView()
    })
    SomeActionButton(title: "Some Custom Stuff") {
        MatchedTitle("Hello")
    }
}, footer: {
    FooterView(
        primaryView: {
            Link(destination: URL(string: "https://opensource.org/licenses/MIT")!) {
                Text("MIT License")
                    .underline()
            }
        },
        secondaryView: {
            Text("© 2025 Example Inc.")
        }
    )
})
```

## License

Licensed under the [MIT license](https://github.com/CodeEditApp/AboutWindow/blob/main/LICENSE.md)
