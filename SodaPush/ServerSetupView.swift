import SwiftUI

struct ServerSetupView: View {
    @EnvironmentObject private var store: AppStore
    @State private var serverURL = "https://"
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("Server URL (HTTPS)", text: $serverURL)
                }

                Section("Account") {
                    TextField("Username", text: $username)
                    SecureField("Password", text: $password)
                }

                if let error = store.sessionError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Button(action: signIn) {
                    if store.isSigningIn {
                        ProgressView()
                    } else {
                        Text("Sign In")
                    }
                }
                .disabled(store.isSigningIn || !canSignIn)
            }
            .formStyle(.grouped)
            .navigationTitle("Connect to SodaPush")
        }
        .task {
            if serverURL == "https://" {
                serverURL = store.suggestedServerURL
            }
        }
    }

    private var canSignIn: Bool {
        !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
    }

    private func signIn() {
        Task {
            await store.login(
                serverURL: serverURL,
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
        }
    }
}
