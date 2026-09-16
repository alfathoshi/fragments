//
//  fragmentsWidgetLiveActivity.swift
//  fragmentsWidget
//
//  Created by Muhammad Bintang Al-Fath on 9/16/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct fragmentsWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct fragmentsWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: fragmentsWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension fragmentsWidgetAttributes {
    fileprivate static var preview: fragmentsWidgetAttributes {
        fragmentsWidgetAttributes(name: "World")
    }
}

extension fragmentsWidgetAttributes.ContentState {
    fileprivate static var smiley: fragmentsWidgetAttributes.ContentState {
        fragmentsWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: fragmentsWidgetAttributes.ContentState {
         fragmentsWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: fragmentsWidgetAttributes.preview) {
   fragmentsWidgetLiveActivity()
} contentStates: {
    fragmentsWidgetAttributes.ContentState.smiley
    fragmentsWidgetAttributes.ContentState.starEyes
}
