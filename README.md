# SodaPush Management Client

SodaPush-Client_Swift is the native SwiftUI operator client for a deployed
[SodaPush Server](https://github.com/guoPhineas/SodaPush-Server). It is intended
for administrators and developers; business applications use
[SodaPush-SDK_Swift](https://github.com/guoPhineas/SodaPush-SDK_Swift) instead.

## Requirements

- Xcode 27 or later
- iOS 27 or later, or macOS 14 or later
- A deployed SodaPush Server at an HTTPS origin URL
- An owner account created through `POST /v1/bootstrap`

The server URL must be an origin such as `https://push.example.com`. Paths,
query strings, fragments, and embedded credentials are rejected.

## Features

- Sign in with a SodaPush account
- Validate a restored session through `GET /v1/me`
- Store the bearer token in the system Keychain
- List applications visible to the account
- Inspect device installation IDs, platform, environment, and status without exposing raw APNs tokens
- Submit alert pushes to all active development or production devices
- Display separate loading, empty, failure, and success states
- Sign out and remove the active token

Server bootstrap, application creation, APNs credential upload, registration-key
rotation, and account administration remain API-only operations. Follow the
Server README for first-time provisioning.

## Architecture

- `SodaPushApp` owns and injects the main-actor `AppStore`.
- `AppStore` models authentication and collection-loading states, validates restored sessions, and coordinates persistence.
- Actor-isolated `APIClient` performs typed `Codable` requests and maps the Server error envelope, including request IDs.
- `KeychainStore` persists access tokens and surfaces Keychain failures.
- SwiftUI views own operation-specific UI state such as device loading and push submission.

## Server contract

The client calls:

- `POST /v1/auth/login`
- `GET /v1/me`
- `GET /v1/apps`
- `GET /v1/apps/:appID/devices`
- `POST /v1/apps/:appID/pushes`

Public JSON fields use camelCase. Authenticated requests use
`Authorization: Bearer <access-token>`. A `401` response clears the active local
session and returns the UI to sign-in.

## Build

Open `SodaPush.xcodeproj` in Xcode and select the shared `SodaPush` scheme, or
build from the command line without code signing:

```sh
xcodebuild -project SodaPush.xcodeproj -scheme SodaPush \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/SodaPushClientDerived \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project SodaPush.xcodeproj -scheme SodaPush \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/SodaPushClientIOS \
  CODE_SIGNING_ALLOWED=NO build
```

For a signed device build, select your own development team and change the
bundle identifier if required.

## Usage

1. Deploy and bootstrap SodaPush Server.
2. Create an application and upload its APNs credential through the Server API.
3. Launch this client and enter the Server HTTPS origin, username, and password.
4. Select an application to inspect devices.
5. Choose the APNs environment and submit an alert push.

The Server accepts the job and returns a job ID. Delivery occurs asynchronously
on Cloudflare and inline on the current Node.js runtime.

## Repository layout

- `SodaPush/APIClient.swift`: typed authenticated HTTP transport
- `SodaPush/AppStore.swift`: authentication, persistence, and application state
- `SodaPush/Models.swift`: API and view-domain models
- `SodaPush/KeychainStore.swift`: bearer-token storage
- `SodaPush/ContentView.swift`: authentication-state routing
- `SodaPush/DashboardView.swift`: application navigation
- `SodaPush/AppDetailView.swift`: device list and push composer
- `SodaPush/ServerSetupView.swift`: Server sign-in
