import Darwin
import Testing
@testable import PTYKit

@Test func getWinsize_afterOpenPTY_returnsRequestedSize() throws {
    let (master, slave) = try Posix.openPTY(cols: 80, rows: 24)
    defer {
        close(master)
        close(slave)
    }

    let winsize = Posix.getWinsize(fd: master)
    #expect(winsize?.cols == 80)
    #expect(winsize?.rows == 24)
}

@Test func getWinsize_afterResize_returnsNewSize() throws {
    let (master, slave) = try Posix.openPTY(cols: 80, rows: 24)
    defer {
        close(master)
        close(slave)
    }

    try Posix.resize(fd: master, cols: 120, rows: 40)

    let winsize = Posix.getWinsize(fd: master)
    #expect(winsize?.cols == 120)
    #expect(winsize?.rows == 40)
}

@Test func getWinsize_onClosedFD_returnsNil() throws {
    let (master, slave) = try Posix.openPTY()
    close(master)
    close(slave)

    #expect(Posix.getWinsize(fd: master) == nil)
}
