//
//  MomentViewModel.swift
//  fragments
//
//  Created on 9/17/26.
//

import SwiftUI

@Observable
@MainActor
final class MomentsViewModel {
    var momentManager: MomentManager
    var isEditing: Bool = false
    var editingCollection: FolderCollection? = nil
    var selectedDetailCollection: FolderCollection? = nil
    
    init(momentManager: MomentManager = MomentManager.shared) {
        self.momentManager = momentManager
    }
    
    func handleMomentSelection(_ collection: FolderCollection) {
        if isEditing {
            editingCollection = collection
        } else {
            selectedDetailCollection = collection
        }
    }
    
    func toggleEditing() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            isEditing.toggle()
        }
    }
}
