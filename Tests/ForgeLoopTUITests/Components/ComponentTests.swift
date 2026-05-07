import Testing
@testable import ForgeLoopTUI

// MARK: - Component Protocol

@Test func testEmptyComponent() {
    let empty = EmptyComponent()
    #expect(empty.render(width: 80).isEmpty)
}

@Test func testTextInputComponent() {
    let input = TextInputComponent(prompt: "> ", value: "hello")
    let lines = input.render(width: 80)
    #expect(lines == ["> hello"])
}

@Test func testListPickerComponent() {
    let picker = ListPickerComponent(items: ["A", "B", "C"], selectedIndex: 1)
    let lines = picker.render(width: 80)
    #expect(lines.count == 3)
    #expect(lines[0] == "  A")
    #expect(lines[1] == "> B")
    #expect(lines[2] == "  C")
}

// MARK: - VStack

@Test func testVStackRendersComponentsInOrder() {
    let vstack = VStack(spacing: 0) {
        TextInputComponent(prompt: "A: ", value: "a")
        TextInputComponent(prompt: "B: ", value: "b")
    }
    let lines = vstack.render(width: 80)
    #expect(lines.count == 2)
    #expect(lines[0] == "A: a")
    #expect(lines[1] == "B: b")
}

@Test func testVStackSpacing() {
    let vstack = VStack(spacing: 2) {
        TextInputComponent(prompt: "A: ", value: "a")
        TextInputComponent(prompt: "B: ", value: "b")
    }
    let lines = vstack.render(width: 80)
    #expect(lines.count == 4)
    #expect(lines[0] == "A: a")
    #expect(lines[1] == "")
    #expect(lines[2] == "")
    #expect(lines[3] == "B: b")
}

@Test func testVStackNested() {
    let vstack = VStack(spacing: 1) {
        VStack(spacing: 0) {
            TextInputComponent(prompt: "A: ", value: "a")
        }
        TextInputComponent(prompt: "B: ", value: "b")
    }
    let lines = vstack.render(width: 80)
    #expect(lines.count == 3)
    #expect(lines[0] == "A: a")
    #expect(lines[1] == "")
    #expect(lines[2] == "B: b")
}

@Test func testVStackSingleComponent() {
    let vstack = VStack {
        TextInputComponent(prompt: "Only: ", value: "one")
    }
    let lines = vstack.render(width: 80)
    #expect(lines == ["Only: one"])
}

@Test func testVStackEmpty() {
    let vstack = VStack(components: [], spacing: 0)
    #expect(vstack.render(width: 80).isEmpty)
}

// MARK: - ComponentBuilder

@Test func testComponentBuilderSixComponents() {
    let vstack = VStack {
        TextInputComponent(prompt: "1: ", value: "a")
        TextInputComponent(prompt: "2: ", value: "b")
        TextInputComponent(prompt: "3: ", value: "c")
        TextInputComponent(prompt: "4: ", value: "d")
        TextInputComponent(prompt: "5: ", value: "e")
        TextInputComponent(prompt: "6: ", value: "f")
    }
    let lines = vstack.render(width: 80)
    #expect(lines.count == 6)
    #expect(lines[0] == "1: a")
    #expect(lines[5] == "6: f")
}

@Test func testComponentBuilderIfElseSameType() {
    let flag = true
    let vstack = VStack {
        TextInputComponent(prompt: "before: ", value: "x")
        if flag {
            TextInputComponent(prompt: "flag: ", value: "yes")
        } else {
            TextInputComponent(prompt: "flag: ", value: "no")
        }
        TextInputComponent(prompt: "after: ", value: "y")
    }
    let lines = vstack.render(width: 80)
    #expect(lines.count == 3)
    #expect(lines[0] == "before: x")
    #expect(lines[1] == "flag: yes")
    #expect(lines[2] == "after: y")
}

@Test func testComponentBuilderIfElseDifferentType() {
    let flag = false
    let vstack = VStack {
        TextInputComponent(prompt: "before: ", value: "x")
        if flag {
            TextInputComponent(prompt: "text: ", value: "yes")
        } else {
            ListPickerComponent(items: ["A", "B"], selectedIndex: 0)
        }
        TextInputComponent(prompt: "after: ", value: "y")
    }
    let lines = vstack.render(width: 80)
    #expect(lines.count == 4)
    #expect(lines[0] == "before: x")
    #expect(lines[1] == "> A")
    #expect(lines[2] == "  B")
    #expect(lines[3] == "after: y")
}

@Test func testComponentBuilderOptionalAbsent() {
    let flag = false
    let vstack = VStack {
        TextInputComponent(prompt: "before: ", value: "x")
        if flag {
            TextInputComponent(prompt: "skip: ", value: "nope")
        }
        TextInputComponent(prompt: "after: ", value: "y")
    }
    let lines = vstack.render(width: 80)
    #expect(lines.count == 2)
    #expect(lines[0] == "before: x")
    #expect(lines[1] == "after: y")
}

@Test func testAnyComponentWraps() {
    let wrapped = AnyComponent(TextInputComponent(prompt: "> ", value: "x"))
    #expect(wrapped.render(width: 80) == ["> x"])
}

// MARK: - FrameComposer

@Test func testFrameComposerRendersCommittedAndLive() {
    let composer = FrameComposer(
        committed: [
            AnyComponent(TextInputComponent(prompt: "C: ", value: "committed"))
        ],
        live: [
            AnyComponent(TextInputComponent(prompt: "L: ", value: "live"))
        ]
    )
    let frame = composer.render(width: 80)
    #expect(frame.committed == ["C: committed"])
    #expect(frame.live == ["L: live"])
}

@Test func testFrameComposerEmpty() {
    let composer = FrameComposer()
    let frame = composer.render(width: 80)
    #expect(frame.committed.isEmpty)
    #expect(frame.live.isEmpty)
    #expect(frame.cursorOffset == nil)
}

@Test func testComposedFrameDefaults() {
    let frame = ComposedFrame()
    #expect(frame.committed.isEmpty)
    #expect(frame.live.isEmpty)
    #expect(frame.cursorOffset == nil)
}

@Test func testFrameComposerCursorOffset() {
    let composer = FrameComposer(
        live: [AnyComponent(TextInputComponent(prompt: "> ", value: "abc"))]
    )
    let frame = composer.render(width: 80, cursorOffset: 5)
    #expect(frame.cursorOffset == 5)
}
