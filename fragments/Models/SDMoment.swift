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
    public var text: String?
    public var duration: String?
    public var audioWaveform: [Double]
    public var typeRawValue: String?
    public var createdAt: Date?
    public var orderIndex: Int = 0
    
    public var moment: SDMoment?

    public init(
        id: UUID = UUID(),
        title: String = "",
        subtitle: String? = nil,
        systemImage: String? = nil,
        imageName: String? = nil,
        gradientRGBAStrings: [String] = [],
        tag: String? = nil,
        text: String? = nil,
        duration: String? = nil,
        audioWaveform: [Double] = [],
        typeRawValue: String? = nil,
        createdAt: Date? = nil,
        orderIndex: Int = 0
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.imageName = imageName
        self.gradientRGBAStrings = gradientRGBAStrings
        self.tag = tag
        self.text = text
        self.duration = duration
        self.audioWaveform = audioWaveform
        self.typeRawValue = typeRawValue
        self.createdAt = createdAt
        self.orderIndex = orderIndex
    }

    public convenience init(from item: FolderItem, orderIndex: Int = 0) {
        self.init(
            id: item.id,
            title: item.title,
            subtitle: item.subtitle,
            systemImage: item.systemImage,
            imageName: item.imageName,
            gradientRGBAStrings: item.gradientColors.map { $0.toRGBAString() },
            tag: item.tag,
            text: item.text,
            duration: item.duration,
            audioWaveform: item.audioWaveform?.map { Double($0) } ?? [],
            typeRawValue: item.type?.rawValue,
            createdAt: item.createdAt,
            orderIndex: orderIndex
        )
    }

    public func toFolderItem() -> FolderItem {
        let colors = gradientRGBAStrings.map { Color.fromRGBAString($0) }
        let waveform = audioWaveform.map { CGFloat($0) }
        let type = typeRawValue.flatMap { FragmentType(rawValue: $0) }
        return FolderItem(
            id: id,
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            imageName: imageName,
            gradientColors: colors.isEmpty ? [Color.blue.opacity(0.8), Color.purple.opacity(0.8)] : colors,
            tag: tag,
            text: text,
            duration: duration,
            audioWaveform: waveform.isEmpty ? nil : waveform,
            type: type,
            createdAt: createdAt
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
    public var orderedItemIDs: [String] = []
    
    @Relationship(deleteRule: .cascade, inverse: \SDMomentItem.moment)
    public var items: [SDMomentItem]

    public init(
        id: UUID = UUID(),
        name: String,
        location: String,
        date: Date,
        colorRGBAString: String? = nil,
        items: [SDMomentItem] = [],
        orderedItemIDs: [String] = []
    ) {
        self.id = id
        self.name = name
        self.location = location
        self.date = date
        self.colorRGBAString = colorRGBAString
        self.items = items
        self.orderedItemIDs = orderedItemIDs
    }

    public convenience init(from collection: FolderCollection) {
        let sdItems = collection.items.enumerated().map { SDMomentItem(from: $0.element, orderIndex: $0.offset) }
        let orderIDs = collection.items.map { $0.id.uuidString }
        self.init(
            id: collection.id,
            name: collection.name,
            location: collection.location,
            date: collection.date,
            colorRGBAString: collection.color?.toRGBAString(),
            items: sdItems,
            orderedItemIDs: orderIDs
        )
    }

    public func toFolderCollection() -> FolderCollection {
        var orderedSDItems: [SDMomentItem] = []
        if !orderedItemIDs.isEmpty {
            let idMap = Dictionary(uniqueKeysWithValues: items.map { ($0.id.uuidString, $0) })
            for idStr in orderedItemIDs {
                if let itm = idMap[idStr] {
                    orderedSDItems.append(itm)
                }
            }
            for itm in items where !orderedItemIDs.contains(itm.id.uuidString) {
                orderedSDItems.append(itm)
            }
        } else {
            orderedSDItems = items.sorted { $0.orderIndex < $1.orderIndex }
        }

        let folderItems = orderedSDItems.map { $0.toFolderItem() }
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

    public func updateItems(from newItems: [FolderItem], in ctx: ModelContext) {
        self.orderedItemIDs = newItems.map { $0.id.uuidString }
        let existingMap = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        var updatedSDItems: [SDMomentItem] = []

        for (index, item) in newItems.enumerated() {
            if let existing = existingMap[item.id] {
                existing.orderIndex = index
                existing.title = item.title
                existing.subtitle = item.subtitle
                existing.text = item.text
                existing.moment = self
                updatedSDItems.append(existing)
            } else {
                let newSD = SDMomentItem(from: item, orderIndex: index)
                newSD.moment = self
                ctx.insert(newSD)
                updatedSDItems.append(newSD)
            }
        }
        self.items = updatedSDItems
    }
}
