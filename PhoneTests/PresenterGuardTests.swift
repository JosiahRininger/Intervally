//
//  PresenterGuardTests.swift
//  IntervallyPhoneTests
//

import Foundation
import Testing

/// Rules for the views of both apps, read from the source tree (which the simulator shares
/// with the Mac), for mistakes that show only on a device, and only now and then:
///
/// - In a list or a form, a modifier on a `Section` or a `ForEach` is copied to every row in
///   it. An alert, dialog or sheet there is one presenter per row on one binding: the first
///   time it shows in a launch the copies race, and it closes itself a moment later (BMI 2.1
///   shipped that). Presenters go on the list, the screen or the one button.
/// - Deleting a preset always asks first. In 1.2 a full swipe, and Delete in the library's
///   menu, deleted one from both devices with nothing asked. A row's swipe actions and menu
///   now only ask, and the question's Delete deletes. A swipe's Delete is red by its tint,
///   never by the destructive role, which takes the row off the list before anything is
///   answered.
@Suite("Presenter guard")
struct PresenterGuardTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    /// The iPhone and iPad app's views, and the watch app's.
    private let views: ViewSources

    init() throws {
        views = try ViewSources(folders: ["Phone", "Sources"], under: Self.root)
    }

    @Test("No alert, dialog or sheet hangs off a Section or a ForEach")
    func presentersOnRows() {
        #expect(views.presentersOnRows() == [])
    }

    @Test("A row's swipe actions and menu never delete without asking")
    func rowActionsAsk() {
        #expect(views.rowActionsThatDelete() == [])
    }

    @Test("A swipe with Delete in it stops at its actions")
    func noFullSwipeDelete() {
        #expect(views.fullSwipeDeletes() == [])
    }

    /// The swipe's Delete is red by its tint (`WorkoutsView`, `PresetListView`).
    @Test("No swipe action has the destructive role")
    func noDestructiveSwipe() {
        #expect(views.destructiveSwipes() == [])
    }

    /// So a moved folder or a renamed wrapper can't leave the rules above nothing to read.
    @Test("The guard reads the views it guards")
    func readsTheViews() {
        #expect(views.files.count > 40)
        #expect(views.presenters.contains("confirmsDelete"), "The delete question counts as a presenter")
        #expect(Set(views.files(calling: "swipeActions")).isSuperset(of: [
            "Phone/Workouts/WorkoutsView.swift", "Sources/Views/PresetListView.swift",
        ]))
        #expect(views.files(calling: "contextMenu").contains("Phone/Workouts/WorkoutsView.swift"))
    }
}

/// The guard's rules on snippets written the way the app's views are, so a rule that stops
/// finding anything fails here rather than passing above.
@Suite("Presenter guard rules")
struct PresenterGuardRuleTests {
    private func views(_ text: String) -> ViewSources {
        ViewSources(files: [ViewSources.File(path: "Snippet.swift", source: SwiftSource(text))])
    }

    @Test("A presenter on a Section is found, whatever lies between them")
    func onSection() {
        let found = views("""
            Form {
                Section { Text("a") }
                    .alert("A", isPresented: $a) {}
                Section {
                    Text("b")
                } header: {
                    Text("B")
                }
                .listRowBackground(Color.clear)
                #if DEBUG
                .modifier(QAOpen())
                #endif
                .confirmationDialog("B", isPresented: $b) {}
                Section("C") { Text("c") }.sheet(isPresented: $c) { Text("C") }
            }
            """).presentersOnRows()
        #expect(found.map(\.what) == [".alert on Section", ".confirmationDialog on Section", ".sheet on Section"])
        #expect(found.map(\.line) == [3, 13, 14])
    }

    @Test("A presenter on a ForEach is found, as every row gets a copy")
    func onForEach() {
        let found = views("""
            List {
                ForEach(items) { item in
                    Text(item.name)
                }
                .onMove { move($0, $1) }
                .sheet(item: $editing) { item in Editor(item) }
            }
            """).presentersOnRows()
        #expect(found.map(\.what) == [".sheet on ForEach"])
    }

    @Test("On the list or one row a presenter is fine, and in a comment or a string it is nothing")
    func elsewhere() {
        let found = views("""
            List {
                Section {
                    Toggle("On", isOn: $on)
                        .alert("Row", isPresented: $a) {}
                }
                // Section {}.alert("Comment", isPresented: $b) {}
                /* Section {}.alert("Block", isPresented: $c) {} */
                Text("Section {}.alert(")
            }
            .alert("List", isPresented: $d) {}
            """).presentersOnRows()
        #expect(found == [])
    }

    @Test("A string with quotes and brackets inside it hides nothing after it")
    func strings() {
        let found = views("""
            Form {
                Text("Delete “\\(name)”? \\(names.joined(separator: ")")) {")
                Section { Text(#"raw "quoted" \\(not)"#) }
                    .alert("A", isPresented: $a) {}
            }
            """).presentersOnRows()
        #expect(found.map(\.what) == [".alert on Section"])
    }

    @Test("The app's own presenters count: wrappers, their modifiers, and views whose body is a Section")
    func wrappers() {
        let snippet = views("""
            extension View {
                func asks(_ shown: Binding<Bool>, then action: @escaping () -> Void = {}) -> some View {
                    modifier(Asking(shown: shown))
                }
            }

            private struct Asking: ViewModifier {
                @Binding var shown: Bool

                func body(content: Content) -> some View {
                    content.alert("Sure?", isPresented: $shown) {}
                }
            }

            struct Rows: View {
                var body: some View {
                    Section { Text("a") }
                }
            }

            struct Screen: View {
                var body: some View {
                    List {
                        Section {}.asks($a)
                        Rows().asks($b)
                        Section {}.modifier(Asking(shown: $c))
                        Text("d").asks($d)
                    }
                    .asks($e)
                }
            }
            """)
        #expect(snippet.presenters.contains("asks"))
        #expect(snippet.presentingModifiers == ["Asking"])
        #expect(snippet.rowCopiers == ["Section", "ForEach", "Rows"])
        #expect(snippet.presentersOnRows().map(\.what) == [".asks on Section", ".asks on Rows", ".modifier on Section"])
    }

    /// The library's card as 1.2 had it, and the system's own swipe to delete.
    @Test("A swipe or a menu that deletes outright is found, and so is a full swipe that would")
    func deletesOutright() {
        let snippet = views("""
            card
                .swipeActions(edge: .trailing) {
                    if actions.canDelete {
                        Button(role: .destructive) {
                            actions.delete(workout)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .contextMenu {
                    Button(role: .destructive) {
                        store.delete(workout)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            ForEach(store.workouts) { Row($0) }
                .onDelete { store.delete(at: $0) }
            """)
        #expect(snippet.rowActionsThatDelete().map(\.line) == [5, 13, 19])
        #expect(snippet.rowActionsThatDelete().map(\.what) == ["delete( in .swipeActions", "delete( in .contextMenu", ".onDelete"])
        #expect(snippet.fullSwipeDeletes().map(\.line) == [2])
        // Only the swipe's: a menu's destructive role takes nothing off the list.
        #expect(snippet.destructiveSwipes().map(\.line) == [4])
    }

    @Test("Swipes and menus that only ask pass, and a swipe with no Delete in it may run on a full swipe")
    func onlyAsks() {
        let snippet = views("""
            card
                .swipeActions(edge: .leading) {
                    Button { copy(workout) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button { deleting = workout } label: { Label("Delete", systemImage: "trash") }
                        .tint(.red)
                    Button { renaming = workout } label: { Label("Rename", systemImage: "pencil") }
                }
                .contextMenu {
                    Button(role: .destructive) { deleting = workout } label: { Label("Delete", systemImage: "trash") }
                }
            """)
        #expect(snippet.rowActionsThatDelete() == [])
        #expect(snippet.fullSwipeDeletes() == [])
        #expect(snippet.destructiveSwipes() == [])
    }
}
