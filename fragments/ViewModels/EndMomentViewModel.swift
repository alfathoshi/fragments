//
//  EndMomentViewModel.swift
//  fragments
//
//  Created on 9/17/26.
//

import SwiftUI

@Observable
@MainActor
final class EndMomentViewModel {
    var momentName: String = ""
    var selectedCategory: String = "Life"
    var selectedTheme: FolderThemeColor = FolderThemeColor.allThemes[0]
    var location: String
    var showDiscardConfirmation: Bool = false
    
    let categoryOptions = [
        "Life", "Travel", "Friends", "Nature", "Creative", "Quiet", "Work"
    ]
    
    let session: MomentSession
    
    init(session: MomentSession) {
        self.session = session
        self.location = session.location
    }
    
    var defaultPlaceholder: String {
        let hour = Calendar.current.component(.hour, from: session.startDate)
        let timePeriod: String
        switch hour {
        case 5..<12: timePeriod = "Morning"
        case 12..<17: timePeriod = "Afternoon"
        case 17..<21: timePeriod = "Evening"
        default: timePeriod = "Night"
        }
        return "\(timePeriod) \(selectedCategory)"
    }
    
    func handleSave(onSave: (String, String, Color?, String) -> Void) {
        let name = momentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? defaultPlaceholder
            : momentName.trimmingCharacters(in: .whitespacesAndNewlines)

        onSave(name, selectedCategory, selectedTheme.color, location)
    }
}
