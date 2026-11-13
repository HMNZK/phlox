import AppBootstrap
import AppKit
import Darwin
import StructuredChatKit

@main
@MainActor
enum SessionRuntimeEntry {
    static func main() {
        switch SessionRuntimeLaunchRole(arguments: ProcessInfo.processInfo.arguments) {
        case .graphical:
            PhloxApp.main()
        case .sessionHolder:
            ProcessHolderMain.run()
        case .sessionRuntime:
            guard setsid() >= 0 else {
                FileHandle.standardError.write(Data("Session runtime could not detach (\(errno))\n".utf8))
                exit(1)
            }
            SessionRuntimeHost.run()
        }
    }
}
