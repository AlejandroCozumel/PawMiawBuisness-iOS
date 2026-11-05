//
//  Pills.swift
//  PawMiawNegocios
//
//  Two small shared pieces: a choice among a few values drawn as pills that
//  wrap (a mood, a severity, a kind), and a row of overlapping pet faces
//  with "+N" (a group, a family's pets on one visit).
//

import SwiftUI

/// A choice among a few values as wrapping pills (one shared FilterChip each): the
/// web's Segmented. The pills of Stays, Hospital, Schedule and Home's requests.
struct PillPicker<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    /// A second tap on the chosen pill sets this (nothing chosen); nil keeps it chosen.
    var cleared: Value? = nil

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(options, id: \.value) { option in
                FilterChip(title: option.title, isSelected: selection == option.value) {
                    if let cleared, selection == option.value { selection = cleared } else { selection = option.value }
                }
            }
        }
    }
}

extension PillPicker {
    /// Over a choice that may be empty; with `allowsNone` a second tap clears it.
    init<Wrapped: Hashable>(options: [(value: Wrapped, title: String)], choice: Binding<Wrapped?>, allowsNone: Bool = false) where Value == Wrapped? {
        self.options = options.map { (value: Optional($0.value), title: $0.title) }
        self._selection = choice
        self.cleared = allowsNone ? .some(nil) : nil
    }
}

/// A few pets' faces, overlapping, and "+N" for the rest: the one stack of faces of Services,
/// Stays, the Schedule's requests and Home.
struct PetStack: View {
    let pets: [(name: String, species: String?, photo: String?)]
    var size: CGFloat = 30
    /// How many faces show before "+N".
    var max: Int = 4

    var body: some View {
        HStack(spacing: -size / 3) {
            ForEach(Array(pets.prefix(max).enumerated()), id: \.offset) { _, pet in
                PetAvatar(name: pet.name, species: pet.species, photoURL: pet.photo, size: size)
                    .overlay(Circle().stroke(Theme.surface, lineWidth: 2))
            }
            if pets.count > max {
                Text("+\(pets.count - max)").font(.brandText(11, weight: .heavy)).foregroundStyle(Theme.inkStrong)
                    .frame(width: size, height: size).background(Theme.surfaceMuted, in: Circle())
            }
        }
    }
}
