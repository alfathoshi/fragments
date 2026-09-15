//
//  CustomNote.swift
//  fragments
//
//  Created by Muhammad Bintang Al-Fath on 9/14/26.
//

import SwiftUI

public struct CustomNote: View {
    public var onSaveNote: ((String, String, Color) -> Void)? = nil
    public var onClose: (() -> Void)? = nil

    public init(
        onSaveNote: ((String, String, Color) -> Void)? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.onSaveNote = onSaveNote
        self.onClose = onClose
    }

    public init(
        onSaveNote: ((String, Color) -> Void)? = nil,
        onClose: (() -> Void)? = nil
    ) {
        if let legacy = onSaveNote {
            self.onSaveNote = { _, text, color in
                legacy(text, color)
            }
        } else {
            self.onSaveNote = nil
        }
        self.onClose = onClose
    }

    public var body: some View {
        CustomNoteView(onSaveNote: onSaveNote, onClose: onClose)
    }
}
