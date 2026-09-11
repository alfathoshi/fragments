//
//  Item.swift
//  fragments
//
//  Created by Muhammad Bintang Al-Fath on 9/12/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
