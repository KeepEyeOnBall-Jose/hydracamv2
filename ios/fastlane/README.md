fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios build_store

```sh
[bundle exec] fastlane ios build_store
```

Build the release IPA for App Store Connect

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Upload a new beta build to TestFlight

### ios upload_latest_beta

```sh
[bundle exec] fastlane ios upload_latest_beta
```

Upload the latest local IPA to TestFlight without rebuilding

### ios device

```sh
[bundle exec] fastlane ios device
```

Build for physical device

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
