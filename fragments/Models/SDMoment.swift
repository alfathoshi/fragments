//
//  SDMoment.swift
//  fragments
//
//  Created on 9/16/26.
//

import Foundation
import SwiftData
import SwiftUI

@Model
public final class SDMomentItem {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var subtitle: String?
    public var systemImage: String?
    public var imageName: String?
    public var gradientRGBAStrings: [String]
    public var tag: String?
    
    public var moment: SDMoment?

    public init(
        id: UUID = UUID(),
        title: String = "",
        subtitle: String? = nil,
        systemImage: String? = nil,
        imageName: String? = nil,
        gradientRGBAStrings: [String] = [],
        tag: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.imageName = imageName
        self.gradientRGBAStrings = gradientRGBAStrings
        self.tag = tag
    }

    public convenience init(from item: FolderItem) {
        self.init(
            id: item.id,
            title: item.title,
            subtitle: item.subtitle,
            systemImage: item.systemImage,
            imageName: item.imageName,
            gradientRGBAStrings: item.gradientColors.map { $0.toRGBAString() },
            tag: item.tag
        )
    }

    public func toFolderItem() -> FolderItem {
        let colors = gradientRGBAStrings.map { Color.fromRGBAString($0) }
        return FolderItem(
            id: id,
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            imageName: imageName,
            gradientColors: colors.isEmpty ? [Color.blue.opacity(0.8), Color.purple.opacity(0.8)] : colors,
            tag: tag
        )
    }
}

@Model
public final class SDMoment {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var location: String
    public var date: Date
    public var colorRGBAString: String?
    
    @Relationship(deleteRule: .cascade, inverse: \SDMomentItem.moment)
    public var items: [SDMomentItem]

    public init(
        id: UUID = UUID(),
        name: String,
        location: String,
        date: Date,
        colorRGBAString: String? = nil,
        items: [SDMomentItem] = []
    ) {
        self.id = id
        self.name = name
        self.location = location
        self.date = date
        self.colorRGBAString = colorRGBAString
        self.items = items
    }

    public convenience init(from collection: FolderCollection) {
        let sdItems = collection.items.map { SDMomentItem(from: $0) }
        self.init(
            id: collection.id,
            name: collection.name,
            location: collection.location,
            date: collection.date,
            colorRGBAString: collection.color?.toRGBAString(),
            items: sdItems
        )
    }

    public func toFolderCollection() -> FolderCollection {
        let folderItems = items.map { $0.toFolderItem() }
        let color = colorRGBAString.map { Color.fromRGBAString($0) }
        return FolderCollection(
            id: id,
            name: name,
            location: location,
            date: date,
            items: folderItems,
            color: color
        )
    }
}
