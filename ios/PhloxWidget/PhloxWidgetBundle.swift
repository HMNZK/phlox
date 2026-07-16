import SwiftUI
import WidgetKit

@main
struct PhloxWidgetBundle: WidgetBundle {
    var body: some Widget {
        SessionStatusWidget()
        SessionLiveActivity()
    }
}
