# ColimaUI

A native macOS app for managing Colima VMs and Docker containers.

![ColimaUI Screenshot](screenshot.png)

## Features

- **Multi-VM Support**: Create and manage multiple Colima VM profiles
- **Container Management**: View, start, stop, restart, and remove containers
- **Real-time Stats**: Live CPU and memory usage per container
- **Log Viewer**: Stream container logs in real-time
- **Image Management**: List and remove Docker images
- **Volume Management**: List, remove, and prune Docker volumes
- **Cleanup Tools**: Prune dangling images, build cache, and unused data

## Installation

1. Download the latest release from [GitHub Releases](https://github.com/ryanmish/ColimaUI/releases)
2. Unzip and drag `ColimaUI.app` to your Applications folder
3. On first launch, right-click the app and select **Open** (bypasses Gatekeeper for unsigned apps)

Or run this in Terminal to remove the quarantine flag:
```bash
xattr -cr /Applications/ColimaUI.app
```

## Requirements

- macOS 14.0 (Sonoma) or later
- [Colima](https://github.com/abiosoft/colima) installed via Homebrew
- Docker CLI

If you don't have Colima installed, the app will guide you through the installation process.

## Building from Source

Requires [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project.

```bash
# Install XcodeGen if needed
brew install xcodegen

# Clone the repo
git clone https://github.com/ryanmish/ColimaUI.git
cd ColimaUI

# Generate Xcode project
xcodegen generate

# Open in Xcode
open ColimaUI.xcodeproj

# Build and run (Cmd+R)
```

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.

## License

Source Available - Free to use (including commercially), but not for resale. See [LICENSE](LICENSE) for details.
