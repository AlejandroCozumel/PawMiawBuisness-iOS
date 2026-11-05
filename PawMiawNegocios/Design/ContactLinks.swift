//
//  ContactLinks.swift
//  PawMiawNegocios
//
//  Calling a client and opening WhatsApp with them. The app never sends a
//  message by itself: these open the phone or WhatsApp, the person sends.
//

import SwiftUI

enum ContactLinks {
    /// `tel:` for a phone number, nil when there is none.
    static func phone(_ number: String?) -> URL? {
        guard let number = number?.nonEmpty else { return nil }
        let dialable = number.filter { $0.isNumber || $0 == "+" }
        guard dialable.filter(\.isNumber).count >= 7 else { return nil }
        return URL(string: "tel:\(dialable)")
    }

    /// `https://wa.me/…` for a phone number; a 10-digit Mexican number gets +52.
    /// With `text`, WhatsApp opens with it written.
    static func whatsApp(_ number: String?, text: String? = nil) -> URL? {
        guard let number = number?.trimmingCharacters(in: .whitespaces), !number.isEmpty else { return nil }
        let digits = number.filter(\.isNumber)
        guard digits.count >= 10 else { return nil }
        let international = number.hasPrefix("+") ? digits : (digits.count == 10 ? "52" + digits : digits)
        var components = URLComponents(string: "https://wa.me/\(international)")!
        if let text = text?.nonEmpty { components.queryItems = [URLQueryItem(name: "text", value: text)] }
        return components.url
    }

    /// Maps directions to an address.
    static func maps(_ address: String?) -> URL? {
        guard let address = address?.nonEmpty else { return nil }
        var components = URLComponents(string: "https://maps.apple.com/")!
        components.queryItems = [URLQueryItem(name: "daddr", value: address)]
        return components.url
    }
}

/// Call and WhatsApp, as two round icon controls.
struct ContactButtons: View {
    let phone: String?
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 6) {
            if let tel = ContactLinks.phone(phone) {
                IconCircleButton(systemImage: "phone.fill", label: L("Call")) { openURL(tel) }
            }
            if let whatsapp = ContactLinks.whatsApp(phone) {
                IconCircleButton(systemImage: "message.fill", label: "WhatsApp") { openURL(whatsapp) }
            }
        }
    }
}

/// A phone number that calls when tapped.
struct PhoneLink: View {
    let phone: String

    var body: some View {
        if let url = ContactLinks.phone(phone) {
            Link(destination: url) {
                Label(phone, systemImage: "phone.fill").font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.blueText)
            }
        } else {
            Text(phone).font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
        }
    }
}
