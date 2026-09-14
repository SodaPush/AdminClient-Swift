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

- Inspect server health/readiness and complete first-time owner bootstrap
- Sign in, restore sessions from Keychain, switch between saved servers, and sign out
- Validate a restored session through `GET /v1/me`
- Store the bearer token in the system Keychain
- Create, rename, enable, and disable applications
- Inspect device installation IDs, platform, versions, locale, environment, and status without exposing raw APNs tokens
- Deactivate stale devices with an explicit confirmation
- Upload and remove APNs `.p8` credentials without persisting private key material
- Create and revoke SDK registration keys, showing each secret only once with a copy action
- Compose alert, background, Live Activity, or custom JSON pushes for all devices or a selected device set
- Browse push history, inspect delivery results, and poll in-flight jobs until completion
- Manage users and per-app members when the current role allows it
- Display dedicated loading, empty, failure, retry, and success states

## Architecture

- `SodaPushApp` owns and injects the main-actor `AppStore`.
- `AppStore` models authentication and collection-loading states, validates restored sessions, and coordinates persistence.
- Actor-isolated `APIClient` performs typed `Codable` requests and maps the Server error envelope, including request IDs.
- `KeychainStore` persists access tokens and surfaces Keychain failures.
- SwiftUI views own operation-specific UI state such as device loading and push submission.

## Server contract

The client calls:

- `GET /healthz`
- `GET /readyz`
- `GET /v1/bootstrap/status`
- `POST /v1/bootstrap`
- `POST /v1/auth/login`
- `POST /v1/auth/logout`
- `GET /v1/me`
- `GET /v1/apps`
- `POST /v1/apps`
- `GET /v1/apps/:appID`
- `PATCH /v1/apps/:appID`
- `GET|POST /v1/apps/:appID/apns-credentials`
- `DELETE /v1/apps/:appID/apns-credentials/:credentialID`
- `GET|POST /v1/apps/:appID/registration-keys`
- `DELETE /v1/apps/:appID/registration-keys/:keyID`
- `GET /v1/apps/:appID/devices`
- `PATCH /v1/apps/:appID/devices/:installationID?environment=<environment>`
- `GET /v1/apps/:appID/pushes`
- `POST /v1/apps/:appID/pushes`
- `GET /v1/apps/:appID/pushes/:jobID`
- `GET|POST /v1/users` (owner only)
- `PATCH /v1/users/:userID` (owner only)
- `GET /v1/apps/:appID/members`
- `PUT|DELETE /v1/apps/:appID/members/:userID`

Public JSON fields use camelCase. Authenticated requests use
`Authorization: Bearer <access-token>`. A `401` response clears the active local
session and returns the UI to sign-in. The UI hides management actions that are
not available to the current effective app role.

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
- `SodaPush/DashboardView.swift`: workspace navigation and application list
- `SodaPush/AppDetailView.swift`: app overview, status controls, and section navigation
- `SodaPush/DevicesView.swift`: device inventory, filtering, deactivation, and targeting
- `SodaPush/PushesView.swift`: push composer, history, and delivery details
- `SodaPush/CredentialsView.swift`: APNs credentials and registration-key rotation
- `SodaPush/UserManagementView.swift`: owner-only account administration
- `SodaPush/AppMembersView.swift`: per-app member access
- `SodaPush/ServerSetupView.swift`: server inspection, bootstrap, and sign-in
- `SodaPush/DesignSystem.swift`: shared status, metric, clipboard, and date UI helpers
