//
//  AccountSecurityScreen.swift
//  PawMiawNegocios
//
//  Your account (web: routes/provider.account.security.tsx): your profile
//  (name, phone, photo; the email you sign in with), where you are signed
//  in (sign a device out, or every device), and your password (change it
//  with the current one or with a code we email), your professional
//  signature, and deleting the account. One account for the business
//  workspace and for your pets. Signing out of this device is in the shell.
//

import SwiftUI
import PhotosUI

struct AccountSecurityScreen: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        PageScroll {
            ModuleHeader(
                icon: ProviderSection.accountSecurity.headerIcon,
                title: L("Your account"),
                subtitle: L("Your profile, where you are signed in, your signature and your account. It is one account: the same for your business workspace and for your pets."),
                accent: ProviderSection.accountSecurity.headerAccent,
                storageKey: "account-security"
            )
            TeamAccountProfileCard()
            TeamSessionsCard()
            TeamPanel(title: L("One account for everything"), systemImage: "paw-print", tint: Theme.pink) {
                Text(L("Signing a device out here closes PawMiaw on it completely: your pets and your business workspace alike. Your business details are in Settings."))
                    .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            }
            TeamPasswordCard()
            // The professional signature: printed on prescriptions, records, discharges and certificates.
            MySignatureCard()
            TeamAccountDeletionPanel()
        }
        .providerPage(L("Your account"))
    }
}

// MARK: - Profile

private struct TeamAccountProfileCard: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var form = FormState()
    @StateObject private var flash = TeamSavedFlash()
    @State private var profile: TeamUserProfile?
    @State private var failed = false
    @State private var name = ""
    @State private var phone = ""
    @State private var photo = PhotoDraft()
    @State private var saving = false

    private var dirty: Bool {
        guard let profile else { return false }
        return name.trimmingCharacters(in: .whitespaces) != (profile.name ?? "") || phone.trimmingCharacters(in: .whitespaces) != (profile.phone ?? "") || photo.data != nil
    }

    var body: some View {
        TeamSaveSection(
            title: L("Your profile"),
            subtitle: L("Your name and photo as your team and families see them. It is one account: the same in your workspace and with your pets."),
            systemImage: "user-round",
            tint: Theme.blue,
            look: .settings,
            state: flash.state(saving: saving, dirty: dirty),
            saveLabel: L("Save profile"),
            onSave: profile == nil ? nil : { save() },
            onDiscard: { fill() }
        ) {
            if profile == nil {
                if failed {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L("Could not save your profile.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                        PMButton(L("Try again"), variant: .outline, size: .compact) { Task { await load() } }
                    }
                } else { ProgressView().frame(maxWidth: .infinity, minHeight: 64) }
            } else {
                FormScroll(form: form) {
                    VStack(alignment: .leading, spacing: 16) {
                        PhotoField(label: L("Photo"), hint: L("JPG, PNG or WebP, up to 3 MB."), currentURL: profile?.image, draft: $photo, shape: .circle, allowsRemove: false)
                        PMTextField(L("Name"), text: $name, key: "name", form: form, prompt: L("Your name"), capitalization: .words)
                        PMTextField(L("Phone"), text: $phone, key: "phone", form: form, keyboard: .phonePad, optional: true)
                        FormField(label: L("Email"), hint: L("The address you sign in with.")) {
                            Text(profile?.email ?? session.user?.email ?? "—").font(Theme.bodyFont).foregroundStyle(Theme.inkSoft)
                                .frame(maxWidth: .infinity, alignment: .leading).fieldChrome()
                        }
                    }
                    .disabled(saving)
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            profile = try await API.get("/users/me")
            failed = false
            fill()
        } catch { failed = profile == nil }
    }

    private func fill() {
        name = profile?.name ?? ""
        phone = profile?.phone ?? ""
        photo = PhotoDraft()
        form.errors = [:]
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let p = phone.trimmingCharacters(in: .whitespaces)
        let digits = p.filter(\.isNumber).count
        guard form.check([
            ("name", trimmed.isEmpty ? L("Add your name.") : (trimmed.count > 120 ? L("Keep the name under 120 characters.") : nil)),
            ("phone", !p.isEmpty && (digits < 8 || digits > 15) ? L("Finish the phone number, or leave it empty.") : nil),
        ]) else { return }
        saving = true
        Task {
            defer { saving = false }
            do {
                if trimmed != (profile?.name ?? "") || p != (profile?.phone ?? "") {
                    // An empty phone clears it.
                    profile = try await API.patch("/users/me", body: ["name": trimmed, "phone": p])
                }
                if let photo = photo.data {
                    let _: EmptyResponse = try await ImageUpload.upload(photo, to: "/users/me/photo")
                    profile = try? await API.get("/users/me")
                }
                fill()
                flash.mark()
                await session.revalidate()
            } catch {
                form.apply(error, known: ["name": "name", "phone": "phone"])
            }
        }
    }
}

// MARK: - Sessions

private struct TeamSessionsCard: View {
    @EnvironmentObject private var session: SessionStore
    @State private var sessions: [TeamUserSession] = []
    @State private var loaded = false
    @State private var failed = false
    @State private var revokingId: String?
    @State private var confirmAll = false

    var body: some View {
        let ordered = sessions.filter { $0.isCurrent ?? false } + sessions.filter { !($0.isCurrent ?? false) }
        TeamPanel(
            title: L("Connected sessions"),
            subtitle: L("Devices currently signed into your account. Sign out any you don’t recognize."),
            systemImage: "shield-check",
            tint: Theme.aqua
        ) {
            if loaded && !sessions.isEmpty {
                Text("\(sessions.count)")
                    .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.onBlue)
                    .padding(.horizontal, 8).frame(minWidth: 32, minHeight: 32)
                    .background(Theme.blue, in: Capsule())
            }
        } content: {
            if !loaded {
                ProgressView().frame(maxWidth: .infinity, minHeight: 64)
            } else if failed && sessions.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L("Something went wrong. Try again.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    PMButton(L("Try again"), variant: .outline, size: .compact) { Task { await load() } }
                }
            } else if sessions.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    Glyph("shield-check", size: 18).foregroundStyle(Theme.blue)
                        .frame(width: 40, height: 40).background(Theme.surface, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.borderSoft, lineWidth: 1))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Sessions").uppercased()).font(Theme.text(12, weight: .bold)).tracking(1.4).foregroundStyle(Theme.inkSoft)
                        Text(L("No active sessions were found.")).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 2))
            } else {
                VStack(spacing: 12) {
                    ForEach(ordered) { item in row(item) }
                }
            }
            if loaded && !(failed && sessions.isEmpty) {
                // The footer strip: what "all" means, and the coral button.
                let others = sessions.filter { !($0.isCurrent ?? false) }.count
                VStack(alignment: .leading, spacing: 12) {
                    Text(others == 1 ? L("Sign out 1 other device plus this one.") : others > 1 ? LF("Sign out %d other devices plus this one.", others) : L("Signing out all devices ends every session, including this one."))
                        .font(Theme.text(14, weight: .medium)).foregroundStyle(Theme.inkSoft)
                    PMButton(L("Sign out all devices"), systemImage: "log-out", variant: .destructive, fullWidth: true) { confirmAll = true }
                        .disabled(sessions.isEmpty)
                }
                .padding(.horizontal, 16).padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surfaceMuted)
                .overlay(alignment: .top) { RowDivider() }
                .padding(.horizontal, -16).padding(.bottom, -16)
            }
        }
        .task { await load() }
        .sheet(isPresented: $confirmAll) {
            TeamSignOutAllSheet(otherSessions: loaded ? sessions.filter { !($0.isCurrent ?? false) }.count : nil)
        }
    }

    private func row(_ item: TeamUserSession) -> some View {
        let browser = item.browserLabel ?? ""
        let platform = item.platformLabel ?? ""
        let name = item.deviceLabel == "\(browser) on \(platform)" ? LF("%1$@ on %2$@", L(browser), L(platform)) : L(item.deviceLabel ?? L("Unknown session"))
        let current = item.isCurrent ?? false
        let icon: String = {
            let words = "\(item.deviceLabel ?? "") \(platform)".lowercased()
            if words.contains("iphone") || words.contains("android phone") { return "smartphone" }
            if words.contains("ipad") || words.contains("tablet") { return "tablet" }
            if words.contains("android") || words.contains("phone") { return "smartphone" }
            return "laptop"
        }()
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Glyph(icon, size: 20)
                    .foregroundStyle(current ? Theme.inkOnBright : Theme.blue)
                    .frame(width: 44, height: 44)
                    .background(current ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Theme.surfaceMuted), in: Circle())
                    .overlay(Circle().strokeBorder(current ? Theme.blue : Theme.borderSoft, lineWidth: 1))
                VStack(alignment: .leading, spacing: 4) {
                    FlowLayout(spacing: 8) {
                        Text(name).font(.brandHeading(18, relativeTo: .headline)).foregroundStyle(Theme.inkStrong).lineLimit(2)
                        if current {
                            HStack(spacing: 4) { Glyph("shield-check", size: 14); Text(L("This device")) }
                                .font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkOnBright)
                                .padding(.horizontal, 10).frame(height: 26)
                                .background(Theme.lime, in: Capsule())
                                .overlay(Capsule().strokeBorder(Theme.blue, lineWidth: 1))
                        }
                    }
                    Text("\(L(browser)) · \(L(platform))".uppercased()).font(Theme.text(12, weight: .semibold)).tracking(0.5).foregroundStyle(Theme.inkSoft)
                }
                Spacer(minLength: 0)
            }
            if !current {
                PMButton(L("Sign out"), systemImage: "log-out", variant: .destructive, size: .compact, isWorking: revokingId == item.id) { revoke(item) }
            }
            VStack(alignment: .leading, spacing: 10) {
                meta("map-pin", L(item.locationLabel.nonEmpty ?? "Unknown location"))
                meta("earth", item.ipAddress.nonEmpty ?? L("IP unavailable"))
                meta("clock-3", current ? L("Now") : "\(L("Active")) \(DateText.ago(item.lastActiveAt))")
                if let created = item.createdAt { meta("calendar-days", "\(L("Signed in")) \(DateText.day(created))") }
            }
            if let expires = item.expiresAt {
                Text("\(L("Session expires")) \(DateText.date(expires))")
                    .font(Theme.text(11.2, weight: .medium)).foregroundStyle(Theme.inkSoft)
                    .padding(.top, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) { RowDivider() }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(current ? AnyShapeStyle(Theme.wash(Theme.lime, 16)) : AnyShapeStyle(Theme.surfaceMuted), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(current ? Theme.blue : Theme.borderSoft, lineWidth: 2))
    }

    private func meta(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Glyph(icon, size: 14).foregroundStyle(Theme.blue)
            Text(text).lineLimit(1)
        }
        .font(Theme.text(12, weight: .medium)).foregroundStyle(Theme.inkSoft)
    }

    private func load() async {
        do {
            let answer: TeamSessionsResponse = try await API.get("/users/me/sessions")
            sessions = answer.sessions
            failed = false
        } catch { failed = true }
        loaded = true
    }

    private func revoke(_ item: TeamUserSession) {
        revokingId = item.id
        Task {
            defer { revokingId = nil }
            do {
                try await API.send("DELETE", "/users/me/sessions/\(item.id)")
                await load()
            } catch { Toast.error(error) }
        }
    }
}

// MARK: - Password

private struct TeamPasswordCard: View {
    @StateObject private var form = FormState()
    @State private var status: TeamPasswordStatus?
    @State private var open = false
    @State private var useCode = false
    @State private var current = ""
    @State private var code = ""
    @State private var next = ""
    @State private var sentTo: String?
    @State private var resendIn = 0
    @State private var sending = false
    @State private var saving = false

    private var hasPassword: Bool { status?.hasPassword ?? true }
    private var usingCode: Bool { !hasPassword || useCode }
    private var social: String? {
        let names = (status?.socialProviders ?? []).compactMap { ["google": "Google", "apple": "Apple"][$0] }
        if names.isEmpty { return nil }
        return names.count == 1 ? names[0] : LF("%1$@ or %2$@", names[0], names[1])
    }

    var body: some View {
        TeamPanel(title: hasPassword ? L("Password") : L("Create a password"), subtitle: summary, systemImage: "key-round", tint: Theme.lime) {
            if !open {
                PMButton(hasPassword ? L("Change password") : L("Create a password"), systemImage: "key-round", variant: .outline, fullWidth: true) { open = true }
            }
        } content: {
            if open {
                FormScroll(form: form) {
                    VStack(alignment: .leading, spacing: 14) {
                        if usingCode {
                            if let sentTo {
                                PMTextField(LF("Six-digit code we sent to %@", sentTo), text: $code, key: "code", form: form, keyboard: .numberPad)
                                Button(resendIn > 0 ? LF("Send another code in %d s", resendIn) : L("Send another code")) { sendCode() }
                                    .disabled(resendIn > 0 || sending)
                                    .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.blue)
                            } else {
                                Text(hasPassword ? L("We email a six-digit code to your account’s address. Type it here to choose a new password.") : L("We email a six-digit code to your account’s address, to confirm it is you. Type it here to choose your password."))
                                    .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                                PMButton(L("Email me the code"), systemImage: "mail", isWorking: sending) { sendCode() }
                                Color.clear.frame(height: 0).id("code")
                                if let error = form.error("code") { Text(error).font(Theme.text(12, weight: .medium)).foregroundStyle(Theme.coral) }
                            }
                        } else {
                            PMTextField(L("Current password"), text: $current, key: "current", form: form, secure: true)
                            Button(L("I don’t remember it: email me a code")) { useCode = true }
                                .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.blue)
                        }
                        PMTextField(L("New password"), text: $next, key: "next", form: form, prompt: L("At least 8 characters"), secure: true)
                        VStack(spacing: 8) {
                            PMButton(hasPassword ? L("Change password") : L("Create a password"), systemImage: "key-round", fullWidth: true, isWorking: saving) { save() }
                            PMButton(L("Cancel"), variant: .outline, fullWidth: true) { reset() }
                        }
                        if hasPassword && useCode {
                            Button(L("Use my current password")) { useCode = false }
                                .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.blue)
                        }
                    }
                }
                .padding(16)
                .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            }
        }
        .task { status = try? await API.get("/users/me/password") }
        .task(id: resendIn) {
            guard resendIn > 0 else { return }
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { resendIn -= 1 }
        }
    }

    private var summary: String {
        if hasPassword {
            return social.map { LF("You sign in with your email and password, or with %@. Changing the password signs your other devices out.", $0) }
                ?? L("You sign in with your email and password. Changing the password signs your other devices out.")
        }
        let provider = social ?? L("another service")
        return LF("Today you sign in with %1$@, so this account has no password. Create one to also sign in with your email; signing in with %2$@ keeps working.", provider, provider)
    }

    private func reset() {
        open = false; useCode = false; current = ""; code = ""; next = ""; sentTo = nil; resendIn = 0
        form.errors = [:]
    }

    private func sendCode() {
        sending = true
        Task {
            defer { sending = false }
            do {
                let sent: TeamPasswordCodeSent = try await API.post("/users/me/password/code")
                sentTo = sent.email ?? ""
                resendIn = 60
                code = ""
                form.clear("code")
            } catch {
                Toast.error(errorText(error, fallback: L("The code could not be sent. Try again.")))
            }
        }
    }

    private func save() {
        guard form.check([
            ("current", !usingCode && current.isEmpty ? L("Type your current password.") : nil),
            ("code", usingCode && code.filter(\.isNumber).count != 6 ? L("Type the six digits we emailed you.") : nil),
            ("next", next.count < 8 ? L("Password must be at least 8 characters.") : nil),
        ]) else { return }
        saving = true
        Task {
            defer { saving = false }
            do {
                let body: [String: Any?] = usingCode ? ["newPassword": next, "code": code.filter(\.isNumber)] : ["newPassword": next, "currentPassword": current]
                let result: TeamPasswordResult = try await API.put("/users/me/password", body: body)
                let done = (result.created ?? false) ? L("Password created.") : L("Password changed.")
                let others = result.otherSessionsSignedOut ?? 0
                let extra = others > 0 ? " " + LP(others, "1 other device was signed out.", "%d other devices were signed out.") : ""
                Toast.show(done + extra)
                status = TeamPasswordStatus(hasPassword: true, socialProviders: status?.socialProviders)
                reset()
            } catch {
                let field: String? = switch (error as? APIError)?.code {
                case "wrong_password", "no_password": "current"
                case "invalid_code", "proof_required": "code"
                case "password_too_short", "password_too_long", "same_password", "password_compromised": "next"
                default: nil
                }
                if let field {
                    _ = form.check([(field, errorText(error))])
                } else {
                    Toast.error(errorText(error, fallback: L("The password could not be saved. Try again.")))
                }
            }
        }
    }
}

/// "Sign out all devices?" (web `SignOutAllConfirm`): the danger-zone confirmation — the coral
/// band with the log-out mark, what it touches as rows, no word to type.
private struct TeamSignOutAllSheet: View {
    /// The other devices signed in, when the page knows them.
    let otherSessions: Int?
    @EnvironmentObject private var session: SessionStore
    @State private var working = false

    var body: some View {
        ProviderModal(
            title: L("Sign out all devices?"),
            subtitle: L("Danger zone"),
            systemImage: "log-out",
            accent: .coral,
            primaryTitle: working ? L("Signing out…") : L("Sign out all devices"),
            primaryVariant: .destructive,
            isWorking: working,
            primaryIcon: "log-out"
        ) {
            working = true
            Task {
                // Signing every device out ends this session too: leave whether the server answered or not.
                try? await API.send("POST", "/users/me/sessions/revoke-all")
                await session.signOut()
                working = false
            }
        } content: {
            Text(L("This will revoke every session for your account, including this device. You will need to sign in again."))
                .font(Theme.bodyFont).foregroundStyle(Theme.inkStrong)
            if let otherSessions {
                VStack(spacing: 8) {
                    FactRow(label: L("Other devices"), value: "\(otherSessions)")
                    FactRow(label: L("This device"), value: L("Signed out too"))
                }
            }
            Text(L("Active app access on web and mobile will stop the next time each device checks the backend."))
                .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
        }
        .presentationDetents([.medium, .large])
    }
}
