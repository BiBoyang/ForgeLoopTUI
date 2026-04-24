# Long Mixed Markdown Showcase

This fixture is meant to stress terminal readability across a longer mixed-structure document.

## Executive Summary

ForgeLoopTUI should keep this whole file readable when rendered as a single transcript block.
The goal is not pixel-perfect CommonMark fidelity; the goal is stable terminal-friendly hierarchy.

> A good terminal rendering should let you skim structure first.
> Details can stay plain as long as the hierarchy remains obvious.
>> Deep quotes should still look deeper than their parents.
> - Quoted lists should not collapse into the same visual level.
>   - Nested quoted bullets should stay visually nested.

## Checklist

1. Headings should stand out from paragraphs.
2. Ordered and unordered lists should remain distinguishable.
3. Fenced code blocks should not accidentally parse tables.
4. Valid tables should render as tables.
5. Malformed or overly wide tables should degrade to plain Markdown.

- Primary bullet one
  - Nested bullet one
    - Deep nested bullet one
- Primary bullet two
  - Nested bullet two
    1. Ordered child one
    2. Ordered child two

---

## Mixed Narrative

The paragraph below intentionally includes a fairly long line so wrapped output has a realistic chance to happen in a smaller terminal window, especially when the user is watching a streaming assistant response instead of a static file dump.

Here is another paragraph with mixed CJK and ASCII: 在终端里同时出现中文、English、numbers 12345、and punctuation should still feel aligned enough for humans to scan comfortably.

### Valid Table

| Component | Status | Notes |
| --- | ---: | --- |
| heading renderer | 1 | stable enough for demo |
| quote nesting | 2 | now visually clearer |
| table degradation | 3 | prefers safety over fake precision |

### Code Sample

```swift
struct RenderPass {
    let id: String
    let lines: [String]
}

func explain(_ pass: RenderPass) {
    print("render \\(pass.id): \\(pass.lines.count) lines")
}
```

### Degraded Table Cases

| key | value |
| --- | --- |
| missing second column |
| still plain | yes |

| very-wide | content |
| --- | --- |
| xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx | still plain |

### Small Terminal Stress

The next few lines are intentionally hostile to a narrow terminal window and are here to help spot ugly wrapping, duplicated prefixes, or visually collapsed hierarchy.

> This quoted paragraph is intentionally long enough that a relatively small terminal window should wrap it across multiple physical rows, and the visible prefix should still make the quoted structure understandable even after wrapping happens in the terminal emulator.
> - This quoted bullet also runs long on purpose so you can see whether the combination of quote prefix and bullet marker still feels readable when the line is much wider than the viewport.
>   - This deeper quoted bullet is even more aggressive, mixing punctuation, numbers 1234567890, and CJK 终端宽度测试 so wrapped lines are not accidentally mistaken for a sibling item.

- This plain bullet is also intentionally verbose and should remain understandable when wrapped multiple times in a narrow terminal because the first visible marker establishes the structure even if subsequent physical rows are just terminal wraps.
  - Nested bullet with a deliberately long explanation that should still feel like a child item rather than collapsing visually back to its parent when the terminal width is small.
    - Deep child bullet with symbols [alpha/beta/gamma], URLs-like text `example.example.example/path/to/resource`, and mixed 中文 English to pressure wrapping behavior.

ThisLineIsIntentionallyVeryLongWithoutNaturalBreakpointsToSimulateAPathOrIdentifierThatMightShowUpInRealOutputAndItShouldStillRemainVisuallyContainedEvenIfTheTerminalHasToWrapItAwkwardlyAcrossSeveralPhysicalRows

```text
/Users/example/Projects/ForgeLoopTUI/Sources/Rendering/VeryLongFileNameThatKeepsGoing/AnotherNestedDirectory/AndAnotherLevel/render_pass_configuration_snapshot.json
```

## Closing Notes

> Final quote
> 1. Ordered content inside a quote should remain legible.
> 2. The visual tree matters more than decorative styling.

- Final bullet
  - child bullet
    - grandchild bullet

End of fixture.
