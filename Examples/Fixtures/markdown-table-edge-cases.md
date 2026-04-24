# Table Edge Cases

This fixture is optimized for boundary checks instead of ideal presentation.

## Mismatched Column Count Should Stay Plain

| name | score |
| --- | --- |
| alice |
| bob | 7 |

The block above should remain plain Markdown instead of rendering as a box table.

## Escaped Pipes Still Render

| raw | note |
| --- | --- |
| a \| b | escaped pipe |
| `x | y` | code span pipe |

## Wide Table Should Degrade

| key | value |
| --- | --- |
| very-long | xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx |

The wide table above should stay plain Markdown so it does not explode the terminal width.

## CJK Width Still Aligns

| 名称 | 值 |
| --- | --- |
| 测试 | 甲 |
| 示例 | 乙 |
