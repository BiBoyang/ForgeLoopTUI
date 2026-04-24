# Narrow Terminal Showcase

This fixture is tuned for very small terminal widths where wrapping is unavoidable and hierarchy must survive awkward physical line breaks.

## Wrapped Quotes

> This quote is intentionally long and should still feel like a quote when a narrow terminal wraps it across several physical rows.
>> This deeper quote is also long, which helps reveal whether nested quote depth remains visually understandable after wrapping.
> - This quoted bullet should still feel attached to the quote even when the content wraps badly.
>   - This nested quoted bullet goes even longer so the combined quote prefix and bullet marker are stressed together in a tight viewport.

## Wrapped Lists

- This primary bullet is intentionally verbose and is here to show whether a narrow terminal still lets you see the parent-child relationship after multiple physical wraps.
  - This nested bullet continues the same idea with enough words to wrap several times and expose whether indentation feels stable.
    - This deep nested bullet adds mixed content like 中文 English 123456 and punctuation / slashes / underscores to stress wrapping further.

## Wrapped Table

| Column | Value | Notes |
| --- | --- | --- |
| path | /Users/example/Projects/ForgeLoopTUI/Sources/Rendering/Nested/Path/That/Will/Wrap/In/A/Small/Terminal | long path-like content |
| summary | terminal rendering should prefer readable hierarchy over pretending long values fit neatly | explanatory text |

## Degraded Wide Table

| column | payload |
| --- | --- |
| giant | xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx |

## Wrapped Code

```text
/Users/example/Projects/ForgeLoopTUI/Sources/Rendering/VeryLongFileNameThatWillAlmostCertainlyWrapInASmallTerminalWindow/render_configuration_snapshot.json
```

```swift
let wrappedExample = "This string is intentionally long so a very narrow terminal should wrap it in the middle of normal prose-like code content."
```

## Closing

> Final note: if this fixture remains readable, the terminal-oriented formatting is probably doing its job.
