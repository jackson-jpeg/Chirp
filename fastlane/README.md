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

### ios test

```sh
[bundle exec] fastlane ios test
```

Run unit tests on simulator

### ios device_install

```sh
[bundle exec] fastlane ios device_install
```

Build + install on physical iPhone over Tailscale

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build + upload to TestFlight

### ios release

```sh
[bundle exec] fastlane ios release
```

Submit to App Store review (requires --yes at CLI level)

### ios status

```sh
[bundle exec] fastlane ios status
```

Query App Store Connect pipeline status

----


## Mac

### mac test

```sh
[bundle exec] fastlane mac test
```

Run unit tests

### mac dmg

```sh
[bundle exec] fastlane mac dmg
```

Build signed + notarized DMG for direct distribution

### mac beta

```sh
[bundle exec] fastlane mac beta
```

Upload to Mac App Store TestFlight (stubbed — enable when MAS listing exists)

### mac release

```sh
[bundle exec] fastlane mac release
```

Submit macOS app to MAS review (stubbed)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
