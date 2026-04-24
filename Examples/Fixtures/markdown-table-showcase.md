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

## Code Fence Should Not Parse Tables

```markdown
| raw | table |
| --- | ----- |
| no  | parse |
```

## Quotes And Lists

> Tables should stay stable in a narrow terminal.
> Wide or malformed cases should degrade gracefully.
>> Nested quote depth should still be obvious.
> - Quoted bullets should preserve structure.
>   - Nested quoted bullets should look deeper.

1. Confirm the table borders read cleanly.
2. Confirm list indentation stays readable.

- The tables above should render cleanly.
- The fenced block should render as code, not as a table.
- Nested bullets should keep their indentation.
  - This child bullet should stay obvious.

---

## Normal Text After Tables

- The tables above should render cleanly.
- The fenced block should not accidentally become a table.
