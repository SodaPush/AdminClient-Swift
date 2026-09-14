# SodaPush Admin for Swift

SodaPush Admin is the native SwiftUI operator app for [SodaPush Server](https://github.com/SodaPush/Server). Applications receiving notifications integrate [SodaPush SDK](https://github.com/SodaPush/SDK-Swift).

## Requirements

- Xcode 27+
- iOS 27+ or macOS 14+
- A deployed SodaPush Server at an HTTPS origin

## Features

- Inspect health/readiness, bootstrap the single owner, sign in, and restore Keychain-backed sessions.
- Create users, edit personal account details, rename accounts, reset passwords, and manage per-app roles with selection-based member assignment.
- Upload multiple APNs `.p8` keys, assign each to sandbox or production, and choose a default for each environment.
- Inspect devices with language, locale, custom tags, business user ID, environment, version, and status.
- Send alert, background, Live Activity, or custom JSON pushes.
- Target all devices or select from reported installations, tags, device languages, and business user IDs.
- Select the APNs key per push, with automatic environment-specific defaults.
- Inspect delivery results and delete completed push records.

APNs private-key material is uploaded directly and never persisted by the admin app. Registration-key secrets are shown only once.

## Build

Open `SodaPush.xcodeproj` and select the shared `SodaPush` scheme, or build without signing:

```sh
xcodebuild -project SodaPush.xcodeproj -scheme SodaPush \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  -derivedDataPath /tmp/SodaPushAdminDerived \
  CODE_SIGNING_ALLOWED=NO build
```

For a signed device build, select your development team and use an appropriate bundle identifier.

## First run

1. Enter the server HTTPS origin, such as `https://push.example.com`.
2. Bootstrap an uninitialized server or sign in with an existing account.
3. Create an application and save its one-time SDK registration secret.
4. Add separate APNs signing keys for Development (sandbox) and Production, marking a default for each.
5. Select an audience and send a push.

The server has exactly one immutable owner account. Additional users can be administrators, developers, or viewers. App-level access is managed separately.

## Architecture

- `AppStore` owns main-actor session and workspace state.
- Actor-isolated `APIClient` uses typed `Codable` requests and `async/await` networking.
- SwiftUI views keep lifecycle-bound work in `.task` and `.refreshable`.
- Navigation uses native destinations and tabs rather than view-switching routers.

The client expects public JSON fields in camelCase and authenticates management requests with a bearer token. A `401` clears the active local session.
