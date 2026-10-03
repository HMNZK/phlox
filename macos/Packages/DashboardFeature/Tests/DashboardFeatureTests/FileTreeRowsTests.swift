import Testing
@testable import DashboardFeature

@Suite("ファイルツリーの行とキーボード操作")
struct FileTreeRowsTests {
    @Test("子の上限表示はその子が終わる位置にだけ置く")
    func directoryEnds() {
        let rows = FileTreeRows.visibleRows(childrenByDir: [
            "": [.init(relativePath: "dir", name: "dir", kind: .directory), .init(relativePath: "z", name: "z", kind: .file)],
            "dir": [.init(relativePath: "dir/nested", name: "nested", kind: .directory), .init(relativePath: "dir/b", name: "b", kind: .file)],
            "dir/nested": [.init(relativePath: "dir/nested/a", name: "a", kind: .file)]
        ], expanded: ["dir", "dir/nested"])
        #expect(FileTreeRows.finishedDirectories(after: 0, rows: rows).isEmpty)
        #expect(FileTreeRows.finishedDirectories(after: 1, rows: rows).isEmpty)
        #expect(FileTreeRows.finishedDirectories(after: 2, rows: rows) == ["dir/nested"])
        #expect(FileTreeRows.finishedDirectories(after: 3, rows: rows) == ["dir"])
        #expect(FileTreeRows.finishedDirectories(after: 4, rows: rows).isEmpty)
        #expect(FileTreeRows.action(for: "dir/b", key: .up, rows: rows, expanded: []) == .select("dir/nested/a"))
        #expect(FileTreeRows.action(for: "dir/b", key: .down, rows: rows, expanded: []) == .select("z"))
    }

    @Test("開いている行は単体表示の操作中のファイルだけ")
    func activeFile() {
        var layout = SessionTabLayout()
        layout.open(.file("left.txt"))
        layout.open(.file("right.txt"))
        layout.splitRight(.file("right.txt"))
        #expect(FileTreeRows.openPath(selected: layout.selected, viewMode: .single, commonTerminalSelected: false) == "right.txt")
        layout.select(.file("left.txt"))
        #expect(FileTreeRows.openPath(selected: layout.selected, viewMode: .single, commonTerminalSelected: false) == "left.txt")
        for tab in [ChildTab.conversation, .terminal, .changes, .file("a.txt")] {
            #expect(FileTreeRows.openPath(selected: tab, viewMode: .grid, commonTerminalSelected: false) == nil)
            #expect(FileTreeRows.openPath(selected: tab, viewMode: .single, commonTerminalSelected: true) == nil)
            if tab != .file("a.txt") {
                #expect(FileTreeRows.openPath(selected: tab, viewMode: .single, commonTerminalSelected: false) == nil)
            }
        }
    }

    @Test("開いたファイルにキーボード選択を合わせる")
    func openedSelection() {
        let rows = FileTreeRows.visibleRows(childrenByDir: ["": [
            .init(relativePath: "a.txt", name: "a.txt", kind: .file),
            .init(relativePath: "b.txt", name: "b.txt", kind: .file)
        ]], expanded: [])
        #expect(FileTreeRows.selection(openPath: "a.txt", selectedPath: nil, rows: rows) == "a.txt")
        #expect(FileTreeRows.selection(openPath: "b.txt", selectedPath: "a.txt", rows: rows) == "b.txt")
        #expect(FileTreeRows.selection(openPath: nil, selectedPath: "a.txt", rows: rows) == "a.txt")
        #expect(FileTreeRows.selection(openPath: "hidden/a", selectedPath: "a.txt", rows: rows) == "a.txt")
    }

    @Test("ルート外のリンクは理由を説明し、Finderには解決先を渡す")
    func outsideLinkPresentation() {
        let entry = FileTreeEntry(relativePath: "outside", name: "outside", kind: .symlinkOutsideRoot,
                                  resolvedPath: "/usr")
        #expect(entry.help == "作業ツリーの外を指しているため開けません。→ /usr")
        #expect(entry.finderURL(root: "/workspace").path == "/usr")
        let rows = [FileTreeRows.Row(entry: entry, depth: 0)]
        #expect(FileTreeRows.action(for: "outside", key: .activate, rows: rows, expanded: []) == .explainBlocked("outside"))
        #expect(FileTreeRows.action(for: "outside", key: .right, rows: rows, expanded: []) == nil)
        #expect(!entry.canOpen)
        let file = FileTreeEntry(relativePath: "a.txt", name: "a.txt", kind: .file)
        #expect(file.finderURL(root: "/workspace").path == "/workspace/a.txt")
    }

    @Test("展開したフォルダだけ平坦化し、隠れた選択は親へ戻す")
    func flattenAndSelect() {
        let children = [
            "": [FileTreeEntry(relativePath: "dir", name: "dir", kind: .directory),
                 FileTreeEntry(relativePath: "link", name: "link", kind: .symlinkToDirectory)],
            "dir": [FileTreeEntry(relativePath: "dir/a", name: "a", kind: .file)],
            "link": [FileTreeEntry(relativePath: "link/b", name: "b", kind: .file)]
        ]
        let rows = FileTreeRows.visibleRows(childrenByDir: children, expanded: ["dir", "link"])
        #expect(rows.map(\.id) == ["dir", "dir/a", "link"])
        #expect(rows.map(\.depth) == [0, 1, 0])
        #expect(rows[1].isOpen("dir/a"))
        #expect(!rows[0].isOpen("dir"))
        let collapsed = FileTreeRows.visibleRows(childrenByDir: children, expanded: [])
        #expect(FileTreeRows.visibleSelection("dir/a", rows: collapsed) == "dir")
        #expect(FileTreeRows.action(for: "dir", key: .right, rows: collapsed, expanded: []) == .expand("dir"))
        #expect(FileTreeRows.action(for: "dir", key: .right, rows: rows, expanded: ["dir"]) == .select("dir/a"))
        #expect(FileTreeRows.action(for: "dir", key: .left, rows: rows, expanded: ["dir"]) == .collapse("dir"))
        #expect(FileTreeRows.action(for: "dir/a", key: .left, rows: rows, expanded: ["dir"]) == .select("dir"))
        #expect(FileTreeRows.action(for: "dir", key: .activate, rows: rows, expanded: ["dir"]) == .collapse("dir"))
        #expect(FileTreeRows.action(for: "dir/a", key: .activate, rows: rows, expanded: []) == .open("dir/a"))
        #expect(FileTreeRows.action(for: "link", key: .activate, rows: rows, expanded: []) == nil)
    }
}
