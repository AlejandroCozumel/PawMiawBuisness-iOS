//
//  BrandFont.swift
//  PawMiawNegocios (copied from the family app)
//
//  Brand manual v1.0 typography, shared with the web design system:
//    headings  → Fredoka SemiBold  (--font-heading)
//    body / UI → Nunito Sans       (--font-sans)
//
//  The project uses GENERATE_INFOPLIST_FILE = YES, so there is no Info.plist to
//  carry a UIAppFonts key. Instead the bundled TTFs are registered at launch
//  with Core Text. Both families ship as static instances (Fredoka SemiBold;
//  Nunito Sans Regular/Medium/SemiBold/Bold/ExtraBold) so every weight renders
//  exactly like the web instead of relying on a variable-font default. Their
//  SIL OFL licenses ship beside them and are shown under Account → Legal.
//
//  Dancing Script (OFL too) is not a brand face: it draws typed signatures,
//  the same font the backend stamps them in (`Font.signatureScript`).
//

import SwiftUI
import CoreText

enum BrandFonts {
    /// Register every bundled `.ttf` with Core Text. Safe to call more than once.
    static func registerAll() {
        let names = [
            "Fredoka-SemiBold",
            "NunitoSans-Regular",
            "NunitoSans-Medium",
            "NunitoSans-SemiBold",
            "NunitoSans-Bold",
            "NunitoSans-ExtraBold",
            "DancingScript-Regular",
        ]

        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
                #if DEBUG
                print("[BrandFonts] Missing font resource: \(name).ttf")
                #endif
                continue
            }

            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                // Already-registered is fine; surface anything else in debug.
                #if DEBUG
                if let error = error?.takeUnretainedValue() {
                    let code = CFErrorGetCode(error)
                    if code != CTFontManagerError.alreadyRegistered.rawValue {
                        print("[BrandFonts] Failed to register \(name): \(error)")
                    }
                }
                #endif
            }
        }
    }

    /// PostScript name of the Nunito Sans static instance closest to a SwiftUI weight.
    static func textPostScriptName(for weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light, .regular:
            return "NunitoSans-Regular"
        case .medium:
            return "NunitoSans-Medium"
        case .semibold:
            return "NunitoSans-SemiBold"
        case .bold:
            return "NunitoSans-Bold"
        case .heavy, .black:
            return "NunitoSans-ExtraBold"
        default:
            return "NunitoSans-Regular"
        }
    }
}

extension Font {
    /// Fredoka SemiBold — the web's `--font-heading`. Scales with Dynamic Type.
    static func brandHeading(_ size: CGFloat, relativeTo style: TextStyle = .body) -> Font {
        .custom("Fredoka-SemiBold", size: size, relativeTo: style)
    }


    /// Nunito Sans — the web's `--font-sans`. Picks the matching static weight.
    static func brandText(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        relativeTo style: TextStyle = .body
    ) -> Font {
        .custom(BrandFonts.textPostScriptName(for: weight), size: size, relativeTo: style)
    }

    /// Dancing Script — how a typed signature looks everywhere (the backend stamps the same font).
    static func signatureScript(_ size: CGFloat) -> Font {
        .custom("DancingScript-Regular", fixedSize: size)
    }
}
