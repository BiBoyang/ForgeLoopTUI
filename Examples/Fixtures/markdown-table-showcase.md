# Table Showcase

This fixture is optimized for visually checking table rendering.

## Basic Table

| Name  | Score |
| ----- | ----: |
| Alice |    99 |
| Bob   |     7 |
| Carol |    42 |

## Alignment

| Item   | Qty | Price |
| :----- | ---: | ----: |
| Pencil |   2 |  1.50 |
| Eraser |   1 |  0.80 |
| Ruler  |   3 |  2.00 |

## CJK Width

| 名称 | 值 |
| ---- | --- |
| 测试 | 甲 |
| 示例 | 乙 |

## Code Fence Should Stay Plain

```markdown
| raw | table |
| --- | ----- |
| no  | parse |
```

## Normal Text After Tables

- The tables above should render cleanly.
- The fenced block should stay as plain Markdown text.
