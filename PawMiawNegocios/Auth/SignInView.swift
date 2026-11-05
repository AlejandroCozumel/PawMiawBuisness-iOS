//
//  SignInView.swift
//  PawMiawNegocios
//
//  Sign in with the PawMiaw account the business uses on the web. A business
//  is created on the web (pawmiaw.com/providers); this app works in it.
//

import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var form = FormState()
    @State private var email = ""
    @State private var password = ""
    @State private var working = false
    @State private var resetSent = false
    @State private var showReset = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            FormScroll(form: form) {
                VStack(spacing: 22) {
                    VStack(spacing: 14) {
                        Image("BusinessMark").resizable().scaledToFit().frame(width: 108, height: 108)
                            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                            .shadow(color: Theme.blue.opacity(0.25), radius: 18, y: 10)
                        Text(L("PawMiaw Business")).font(.brandHeading(30, relativeTo: .largeTitle)).foregroundStyle(Theme.inkStrong)
                        Text(L("Your clinic, grooming salon, hotel or walks, from your phone."))
                            .font(Theme.bodyFont).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
                    }
                    .padding(.top, 36)

                    Card(padding: 20) {
                        PMTextField(L("Email"), text: $email, key: "email", form: form, prompt: "nombre@negocio.com", keyboard: .emailAddress)
                            .textContentType(.username)
                        PMTextField(L("Password"), text: $password, key: "password", form: form, secure: true)
                            .textContentType(.password)
                        PMButton(L("Sign in"), fullWidth: true, isWorking: working) { signIn() }
                            .padding(.top, 4)
                        Button(L("Forgot your password?")) { showReset = true }
                            .font(Theme.text(15, weight: .bold))
                            .foregroundStyle(Theme.blueText)
                            .frame(maxWidth: .infinity)
                    }

                    VStack(spacing: 6) {
                        Text(L("Don't have your business on PawMiaw yet?")).font(Theme.smallFont).foregroundStyle(Theme.inkSoft)
                        Button(L("Create it on pawmiaw.com")) {
                            openURL(APIConfig.webOrigin.appendingPathComponent("providers"))
                        }
                        .font(Theme.text(15, weight: .bold))
                        .foregroundStyle(Theme.blueText)
                    }
                }
                .padding(20)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Theme.canvas.ignoresSafeArea())
        .sheet(isPresented: $showReset) { ResetPasswordSheet(email: email) }
    }

    private func signIn() {
        let mail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard form.check([
            ("email", mail.isEmpty ? L("Write your email.") : (mail.contains("@") ? nil : L("This email doesn't look right."))),
            ("password", password.isEmpty ? L("Write your password.") : nil),
        ]) else { return }
        working = true
        Task {
            defer { working = false }
            do {
                try await session.signIn(email: mail, password: password)
            } catch let error as APIError where error.status == 401 {
                form.errors = ["password": L("Invalid email or password.")]
                Toast.error(L("Invalid email or password."))
            } catch {
                form.apply(error, known: ["email": "email", "password": "password"])
            }
        }
    }
}

private struct ResetPasswordSheet: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State var email: String
    @State private var working = false

    var body: some View {
        ProviderModal(title: L("Reset your password"), subtitle: L("We'll email you a link to choose a new one."), systemImage: "key.fill", accent: .butter, form: form, primaryTitle: L("Send link"), isWorking: working) {
            let mail = email.trimmingCharacters(in: .whitespacesAndNewlines)
            guard form.check([("email", mail.contains("@") ? nil : L("Write your email."))]) else { return }
            working = true
            Task {
                defer { working = false }
                do {
                    try await session.requestPasswordReset(email: mail)
                    Toast.show(L("If that email has an account, the link is on its way."))
                    dismiss()
                } catch { form.apply(error, known: ["email": "email"]) }
            }
        } content: {
            PMTextField(L("Email"), text: $email, key: "email", form: form, keyboard: .emailAddress)
        }
        .presentationDetents([.medium])
    }
}
