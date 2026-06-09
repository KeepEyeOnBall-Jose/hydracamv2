fastlane documentation
----

# Installation

Make sure Bundler can install fastlane:

```sh
bundle install
```

# Available Actions

## Repo wrapper

From the repository root, prefer `scripts/android_fastlane.sh android <lane>`
instead of running `bundle exec fastlane` directly. The wrapper selects the
Homebrew Ruby/Bundler path used by `android/Gemfile.lock`.

## Android

### android build_store

```sh
[bundle exec] fastlane android build_store
```

Build the release Android App Bundle

### android internal

```sh
[bundle exec] fastlane android internal
```

Upload a build to Google Play Internal testing

### android closed_beta

```sh
[bundle exec] fastlane android closed_beta
```

Upload a build to a Google Play closed testing track

### android production_draft

```sh
[bundle exec] fastlane android production_draft
```

Upload a production draft to Google Play

----

More information about fastlane can be found on [fastlane.tools](https://fastlane.tools).
