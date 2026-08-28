import Foundation

/// TASK-21 `streaming-markdown-garble` investigation fixture.
///
/// 等长重建自 2026-08-29 MinimalAIApp + DeepSeek 流式 dogfood 的缺陷响应
/// （原始模型输出不可回溯，按 `notes/dogfood-2026-08-29-streaming-garble.txt`
/// 的终态 garble 逐节等长重建）。元素覆盖：多级标题、嵌套/有序/任务列表、
/// 多语言代码块（含 CJK 注释与围栏内管道表）、宽表格（降级路径）、对齐表格、
/// 引用与嵌套引用、LaTeX 块、HTML 混用、emoji 行、链接与自动链接。
///
/// 仅供调查测试使用；修复批准后转为回归测试的固定输入。
enum StreamingGarbleFixture {
    static let markdown: String = """
    # Markdown 格式全面测试文档

    我来为你生成一份全面的Markdown格式测试文档，包含各种常用和复杂的格式元素：

    ---

    ## 1. 标题层级

    # 一级标题

    ## 二级标题

    ### 三级标题

    #### 四级标题

    ##### 五级标题

    ###### 六级标题

    ---

    ## 2. 文本样式

    **这是一段粗体文本**，*这是一段斜体文本*，***这是粗斜体***，~~这是删除线~~，这是`行内代码`。

    还可以组合使用：**粗体中包含 *斜体* 和 `代码`**。

    ---

    ## 3. 列表

    ### 无序列表

    - 项目一
    - 项目二
      - 嵌套项目 2.1
      - 嵌套项目 2.2
        - 更深层的项目 2.2.1
    - 项目三

    ### 有序列表

    1. 第一步
    2. 第二步
       1. 子步骤 2.1
       2. 子步骤 2.2
    3. 第三步

    ### 任务列表

    - [x] 已完成任务
    - [x] 另一个已完成任务
    - [ ] 未完成任务
    - [ ] 待办事项

    ---

    ## 4. 代码块

    ### Python

    ```python
    class DataProcessor:
        \"\"\"数据处理类\"\"\"

        def __init__(self, data):
            self.data = data

        @property
        def mean(self) -> float:
            return np.mean(self.data)

        @property
        def std(self) -> float:
            return np.std(self.data)

        def describe(self) -> dict:
            return {
                'mean': self.mean,
                'std': np.std(self.data),
                'count': len(self.data)
            }

    processor = DataProcessor([1, 2, 3, 4, 5])
    print(processor.describe())
    ```

    ### JavaScript

    ```javascript
    // 异步函数示例
    const fetchData = async (url) => {
      try {
        const response = await fetch(url);
        const data = await response.json();
        return data;
      } catch (error) {
        console.error('请求失败:', error);
      }
    };

    // 箭头函数 + 解构
    const user = {
      name: '张三',
      age: 28,
      address: {
        city: '上海',
        zip: '200000'
      },
      hobbies: ['阅读', '编程', '旅行']
    };
    ```

    ---

    ## 5. 表格

    ### 基础表格

    | 姓名 | 年龄 | 部门 | 评分 |
    |:----:|:----:|:----:|:----:|
    | 张三 | 28 | 工程 | 30.5 |
    | 李四 | 35 | 产品 | 27.2 |
    | 王五 | 42 | 市场 | 22.8 |
    | 平均 | - | - | 26.1 |

    ### 复杂表格（多行合并效果）

    | 类别 | 子类 | 2023年 | 2024年 | 增长率 |
    |:-----|:-----|-------:|-------:|-------:|
    |      | 电脑 | 850,000 | 920,000 | +8.2% |
    | 服装 | 男装 | 430,000 | 388,000 | -9.8% |
    | 服装 | 女装 | 520,000 | 610,000 | +17.3% |

    ---

    ## 6. 引用

    > 这是一段引用文本。
    > 可以包含多行内容，以及 inline code。

    > ▹ 嵌套引用
    > > 这是双层引用
    > > • 支持列表

    名言引用：

    > "Talk is cheap. Show me the code."
    > —— Linus Torvalds

    ---

    ## 7. 数学公式（LaTeX）

    ### 块级公式

    $$
    E = mc^2
    $$

    $$
    \\int_{0}^{\\infty} e^{-x^2} dx = \\frac{\\sqrt{\\pi}}{2}
    $$

    $$
    A =
    \\begin{bmatrix}
    10 & 20 \\\\
    30 & 50
    \\end{bmatrix}
    $$

    ---

    ## 8. 链接与图片

    ![示例图片](https://via.placeholder.com/400x200/3498db/ffffff?text=Markdown+测试)

    [Markdown 指南](https://www.markdownguide.org)

    • 自动链接: <https://www.example.com>

    引用式链接：[Markdown][md]

    [md]: https://www.markdownguide.org

    ---

    ## 9. 水平线测试

    水平线1：

    ---

    水平线2：

    ***

    水平线3：

    ___

    ---

    ## 10. 表情符号

    ⚠️ 警告 | ✅ 成功 | ❌ 错误 | 🔥 热门 | ⭐ 推荐 | 💡 提示 | 🚀 快速 | 📌 固定 | 🔧 工具 | 💾 保存

    ---

    ## 11. HTML 混用

    <div align="center">

      <h2>HTML 混合示例</h2>

      <p style="color: #e74c3c; font-weight: bold;">红色加粗文字</p>

      <p><kbd>Ctrl</kbd> + <kbd>C</kbd> 复制快捷键</p>

      <table>
        <tr><td style="background: #2ecc71;">绿色单元格</td></tr>
        <tr><td><details><summary>展开详情</summary>隐藏内容</details></td></tr>
      </table>

    </div>

    ---

    ## 12. 目录结构

    ```text
    project/
    ├── src/
    │   ├── components/
    │   │   ├── Header.tsx
    │   │   └── Footer.tsx
    │   ├── utils/
    │   │   └── helpers.ts
    │   └── index.ts
    ├── public/
    │   └── index.html
    ├── package.json
    └── tsconfig.json
    ```

    ---

    ## 13. 定义列表（HTML）

    <dl>
      <dt>HTML</dt>
      <dd>超文本标记语言（HyperText Markup Language）</dd>

      <dt>CSS</dt>
      <dd>JavaScript 的简称，一种前端脚本语言</dd>
    </dl>

    ---

    ## 14. 提示框

    > [!NOTE]
    > 这是提示内容

    > [!IMPORTANT]
    > 这是重要内容

    > [!CAUTION]
    > 这是小心内容

    ---

    ## 15. 流程图（Mermaid）

    ```mermaid
    graph TD
        A[开始] --> B{是否登录?}
        B -->|是| C[进入主页]
        B -->|否| D[跳转登录]
        D --> E[输入凭证]
        E --> B
        C --> F[选择功能]
        F --> G[加载数据] --> H[渲染页面] --> I[结束]
    ```

    ```mermaid
    gantt
        title 项目甘特图
        dateFormat  YYYY-MM-DD
        section 前期准备
        需求分析       :done, a1, 2024-01-01, 30d
        section 开发
        API开发        :b2, 2024-02-01, 45d
    ```

    ---

    ## 16. 混合示例

    ### 包含所有元素的混合示例

    > ▶ 📌 项目说明
    >
    > | 阶段 | 状态 | 负责人 | 时间 | 优先级 |
    > |:-----|:----:|:------:|:----:|:------:|
    > | 需求分析 | ✅ 完成 | 张三 | 2024/01/15 | 🔴 高 |
    > | 设计稿 | ⏳ 进行中 | 李四 | 2024/02/01 | 🟡 中 |
    >
    > 1. 每日 09:00 站会
    > 2. 每周五代码评审
    > 3. 每日 17:00 进行 *进度同步*
    >
    > 点击 [这里](https://example.com/docs) 查看详细文档，或查看我们的 [GitHub](https://github.com/example)。

    • 分子式：H~2~O，CO~2~

    • 数学：x^2^ + y^2^ = z^2^

    ---

    ## 17. 换行与段落

    这是第一行（后面跟两个空格）
    这是同一段落的第二行

    这是新段落（需要空行）。

    ### 颜色文字

    <span style="color: #e74c3c;">🔴 红色</span> <span style="color: #2ecc71;">🟢 绿色</span> <span style="color: #3498db;">🔵 蓝色</span>

    ---

    ## 18. 折叠面板

    <details>
    <summary>点击展开项目详情</summary>

    项目名称：新一代数据分析平台

    | 阶段 | 完成度 | 备注 |
    |:----:|:-----:|:-----|
    | 需求分析 | 100% | ✅ 已确认 |
    | 后端开发 | 85% | 🚧 联调中 |
    | 前端开发 | 70% | 🔧 核心模块已完成 |

    ```bash
    # 快速启动
    git clone https://github.com/example/project.git
    cd project && npm install && npm run dev
    ```

    </details>

    ---

    ## 19. 嵌套复杂结构

    ### 综合文本

    - 文本内包含代码块：

      ```markdown
      # 这是代码块内的标题
      这是代码块

      | 列1 | 列2 |
      |-----|-----|
      | A   | B   |
      ```

    - 再来一个引用：

      > 引用中包含 **粗体** 与 `代码`。

    ---

    ## 20. 长文本换行测试

    这是一段非常长的中文文本，用于测试自动换行功能。在终端环境中，当一行文本的长度超过终端宽度时，渲染器需要正确地处理换行逻辑，确保文本不会被截断或产生错位的显示效果。这段文字包含了大量的中文字符，每个字符在终端中占据两个单元格的宽度，这对宽度计算提出了更高的要求。

    ---

    ## 21. 最后测试：综合文本

    **粗体**、*斜体*、`代码`、~~删除线~~ 混合出现。

    > 引用 + 代码块混合：

    > ```markdown
    > # 这是引用中的代码块
    > | 列1 | 列2 |
    > |-----|-----|
    > | A   | B   |
    > ```

    ---

    ## 22. 感谢观看

    感谢使用 Markdown 测试！

    ![Twitter](https://img.shields.io/badge/X-黑色?style=for-the-badge&logo=x&logoColor=white&color=000)

    </center>

    ---

    以上就是我为你生成的 Markdown 完整格式测试文档，涵盖了几乎所有常用格式，包含：

    ✅ 标题层级

    ✅ 文本样式（粗体/斜体/删除线等）

    ✅ 列表（有序/无序/任务列表）

    ✅ 代码块（多语言）

    ✅ 表格（含对齐）

    ✅ 引用与嵌套

    ✅ 数学公式

    ✅ 图片与链接

    ✅ 表情符号

    ✅ 特殊HTML

    ✅ Mermaid 图表

    ✅ 折叠面板

    ✅ 测试提醒块

    你现在可以复制这段Markdown代码到任何支持Markdown的编辑器或环境中进行渲染测试了！如果还需要更多特定格式，随时告诉我 😊
    """
}
