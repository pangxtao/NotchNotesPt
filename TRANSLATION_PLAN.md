# NotchNotes 翻译功能 · 开发计划

> 状态：**已实现**（翻译页 + 划词翻译 + 设置窗口，`swift test` 全绿）| 更新日期：2026-10-01

## 一、需求梳理

| # | 需求 | 优先级 |
|---|---|---|
| R1 | 顶栏新增「翻译」tab，点击从笔记页切换到翻译页 | P0 |
| R2 | 翻译页支持输入文本并翻译，中→英、英→中为核心方向 | P0 |
| R3 | 其他语言方向（日/韩/法/德/西/俄等） | P1（引擎天然支持，成本极低） |
| R4 | 应用运行期间，任意 App 内划词后按 `Option + Q`，在鼠标旁弹窗显示译文 | P0 |
| R5 | 弹窗支持复制译文、换向重译 | P1 |
| R6 | 划词译文可一键存为新笔记 | P2（与笔记主功能联动，建议做） |

## 二、翻译引擎（已核实）

阿里云百炼 **Qwen-MT**（千问翻译），基于 Qwen3 微调，支持 92 种语言互译。

**接口**：`POST https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions`（OpenAI 兼容）

```jsonc
{
  "model": "qwen-mt-flash",
  "messages": [{ "role": "user", "content": "待翻译文本" }],
  "translation_options": { "source_lang": "Chinese", "target_lang": "English" },
  "stream": true,
  "stream_options": { "include_usage": true }
}
```

关键约束（官方文档确认）：

- `translation_options` 是**顶层字段**（SDK 中叫 `extra_body`），不是 OpenAI 标准参数。
- `source_lang` 支持 `"auto"` 自动检测；语种可用英文名、中文名或代码（`"English"` / `"en"` 均可）。
- **只支持单轮翻译，不支持 system message** —— 所有配置只能走 `translation_options`。
- 响应为 OpenAI 兼容格式，`choices[0].message.content`；流式为 SSE。

**模型选型**：

| 模型 | 适用 | 流式 | 语种 | 成本 |
|---|---|---|---|---|
| `qwen-mt-flash` | **默认推荐**，通用场景 | ✅ 支持 | 92 | 低 |
| `qwen-mt-plus` | 专业文献 / 正式文书，质量最好 | ❌ | 92 | 高 |
| `qwen-mt-lite` | 实时聊天等极低延迟场景 | ✅ | 31 | 最低 |

> 划词弹窗对**首字延迟**敏感，默认用 `qwen-mt-flash` + 流式；设置里可切 `plus`。
> `qwen-mt-turbo` 官方已停止更新，不使用。

## 三、架构设计

新增 `Sources/NotchNotes/Translation/` 与 `Sources/NotchNotes/Selection/` 两个目录：

| 文件 | 职责 |
|---|---|
| `Translation/TranslationLanguage.swift` | 语言枚举、显示名、API code 映射、常用语言列表 |
| `Translation/TranslationModels.swift` | 请求 / 响应 / 错误 Codable 模型 |
| `Translation/TranslationService.swift` | 网络层：`AsyncThrowingStream<String, Error>` 流式翻译、请求取消、错误映射 |
| `Translation/KeychainStore.swift` | API Key 安全存储（**不落 UserDefaults 明文**） |
| `Translation/TranslationSettingsStore.swift` | API Key、baseURL、模型、默认方向、自动翻译开关、快捷键、术语表 |
| `Translation/TranslationSessionStore.swift` | 翻译页状态机：输入、译文、方向、加载/错误、最近 20 条历史（持久化） |
| `Views/TranslationView.swift` | 翻译页 UI |
| `Views/TranslationPopupView.swift` | 划词弹窗内容 |
| `Selection/SelectionReader.swift` | 读取选中文本：AX API 优先，剪贴板兜底 |
| `Selection/GlobalHotKey.swift` | Carbon `RegisterEventHotKey` 封装（可改键） |
| `Selection/SelectionTranslationController.swift` | 编排：热键 → 取词 → 翻译 → 弹窗定位 → 生命周期 |
| `Selection/TranslationPopupPanel.swift` | 弹窗 NSPanel（非激活态，不抢焦点） |

**改动既有文件**：

- `NotebookView.swift`：顶栏加双模式 tab，body 按 mode 切换笔记页 / 翻译页。
- `NotchPanelController.swift`：**仅**新增 mode 状态与尺寸回调，不动现有触发/拖放逻辑（保护已有 758 行的高风险代码）。
- `AppDelegate.swift`：菜单新增「翻译设置」「检查辅助功能权限」。
- `Resources/Info.plist`：无需新增权限描述键（辅助功能权限走系统弹窗，不读 Info.plist）。

## 四、关键技术难点与对策

### 1. 划词取词（最难的一环）

```
Option+Q → 热键回调 → 读选中文本 → 翻译 → 弹窗
```

取词两条路，必须都实现：

1. **辅助功能 API（首选）**：`AXUIElementCreateSystemWide()` → `kAXFocusedUIElementAttribute` → `kAXSelectedTextAttribute`。
   必须同时做三件事，否则会「经常失败」：
   - **设置 messaging timeout**：`AXUIElementSetMessagingTimeout(0.35s)`。默认 6 秒，目标应用卡顿时会**同步阻塞主线程**，表现就是「按了快捷键没反应」。
   - **沿父链回溯 3 层**：焦点常落在包装层（Web Area / Group）上，真正的可选文本在相邻层级。
   - **`AXSelectedTextRange` + `AXValue` 兜底**：Electron / Java / 部分 PDF 阅读器不实现 `AXSelectedText`，只给 range + value，需要按 UTF-16 码元手工切选区（`SelectionRangeSlicer`）。
2. **剪贴板兜底（必备）**：Chrome / VS Code / Electron 系应用经常返回空。做法：备份剪贴板 → 用 `CGEvent` 模拟 `⌘C` → 读文本 → **还原剪贴板**。三个细节决定成功率：
   - 投递 ⌘C 之前先等 60ms，让物理按住的 Option 松开（否则有概率被拼成 ⌥⌘C）；
   - **`changeCount` 变化 ≠ 数据写完**：不少应用先抬 changeCount 再异步写内容，此时读 `.string` 会拿到空串。必须「读不到就继续等剩余窗口」，而不是立刻 break——旧实现就是在这里既丢了剪贴板还原、又误判成「没有选中文本」；
   - 单次窗口 0.6s 不够，做两轮（0.6s + 0.8s），总耗时仍控制在 1.4s 内。

判定：AX 返回非空直接用；为空则走兜底。取词结果附带 `diagnostic`，失败时在弹窗里显示卡在哪一环。

### 1.1 热键语义

- 弹窗里**已有译文**时再按一次 = 关闭；其余情况一律**重新取词**。
  不能做成「只要弹窗可见就只关闭」——那样第一次取词失败后，第二次按键只是关掉提示，用户会认为快捷键彻底坏了。
- 取词最坏要等 1.4s，因此**弹窗先以加载态挂出来**再取词，避免这段时间里看起来毫无反应。
- 关闭方式：Esc、弹窗右上角 ×、点击弹窗外任意位置。

### 2. 全局热键

用 Carbon `RegisterEventHotKey` 注册 `Option+Q`，而不是 `NSEvent` 全局监听 —— 因为 **Option+Q 在 macOS 上会输入 `œ` 字符**，全局监听无法吞掉按键，会污染用户正在编辑的文档。`RegisterEventHotKey` 会消费事件，且**无需辅助功能权限**即可注册。

### 3. 辅助功能权限（必须提前告知用户）

- 首次触发划词时，用 `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])` 弹系统授权引导，并提供跳转「系统设置 → 隐私与安全性 → 辅助功能」的按钮。
- ⚠️ **开发陷阱**：项目当前用 `codesign --sign -`（ad-hoc 签名）。TCC 权限记录与二进制指纹绑定，**每次重新构建后权限可能失效**，需要重新授权。建议：开发阶段统一用 `./Scripts/package-app.sh` 产出 `.app` 来测试划词功能；正式分发需 Developer ID 签名 + 公证，权限才能稳定留存。
- 未授权时降级：翻译页完全可用，仅划词功能提示去授权。

### 4. 弹窗不抢焦点

划词弹窗必须**不激活应用**，否则用户的选区、输入焦点会被打断。方案：`NSPanel` 子类 + `styleMask` 含 `.nonactivatingPanel`，`orderFrontRegardless()`，`canBecomeKey` 仅在需要点击复制时临时放开。

### 5. 流式解析

`URLSession.bytes(for:)` 逐行读 SSE：跳过空行与 `:` 注释行，取 `data: ` 后的 JSON，`[DONE]` 结束。增量 token 追加到 UI。

### 6. 请求治理

- 输入防抖 600ms，新请求前 `cancel()` 掉上一个（用 `Task` 句柄）。
- 空白/超长（>5000 字）输入拦截。
- 网络错误映射为中文提示（鉴权失败 / 限流 / 超时 / 无网络）。

### 7. API Key 安全

存 macOS Keychain（`kSecClassGenericPassword`），不进 UserDefaults、不进 git。首次使用引导在设置页填写，输入框用 `SecureField`。

## 五、UI 设计

### 5.1 顶栏双模式 tab

复用现有顶栏行（高 28pt），左右分组：

- 左：`● ● ●`（笔记 tab 圆点，保持现状）+ `+` 新建笔记
- 右：`🌐 翻译` 胶囊按钮

点击「翻译」→ 内容区切换为翻译页，右侧按钮变为 `← 笔记`，圆点行隐藏。翻译页内不显示笔记圆点，避免两套 tab 语义混淆。

### 5.2 翻译页布局（左右分栏：左输入 / 右结果）

```
┌──────────────────────────────────────────────────────────────┐
│  ● ● ●  +                                 Notes | Translate  │  顶栏 30pt
├──────────────────────────────────────────────────────────────┤
│  [中 → EN] ⇄   Auto                    qwen-mt-flash ⌄       │  方向条 30pt
├───────────────────────────────┬──────────────────────────────┤
│ SOURCE                   清空 │ TRANSLATION     存笔记  复制 │
│                               │                              │
│ 今天重庆下暴雨，出门记得带伞。 │ It's pouring rain in         │
│                               │ Chongqing today — remember   │
│                               │ to take an umbrella.         │
│                               │                              │
│ 16 characters     [Translate] │ Done in 0.32s                │
└───────────────────────────────┴──────────────────────────────┘
```

- **左右分栏要求面板加宽**：展开宽度统一为 **700–760pt**（无刘海屏幕兜底值 730pt），
  由 `NotchGeometry.layout(for:)` 只按屏幕计算，**与工作区模式无关**。
  笔记页沿用同一档宽度铺满，切换 Notes / Translate 时窗口尺寸完全不动，避免面板来回伸缩。
  若沿用原笔记页的 480pt，左右各只剩约 210pt，中文一行放不下十个字，加宽是必需项。
- 方向条：`中 → EN` 胶囊点击即换向；`Auto` 为自动方向开关（默认开，手动换向后自动关闭）。
- 自动方向：输入含 CJK / 中文标点 → 译英；否则 → 译中。
- 触发方式：输入停顿 600ms 自动翻译；`⌘↩` 立即翻译；`Clear` 清空并回到 Auto。
- 译文流式追加、可选中；完成后出现 `Copy` 与 `Save as note`。
- 错误态：红色提示 + `Retry`；未配置 API Key 时右侧显示引导卡片，点击直达翻译设置。
- 模型切换收在方向条右侧的下拉菜单里，不占额外版面。

### 5.3 划词弹窗（360pt 宽，高度自适应 96–340pt）

```
┌────────────────────────────────┐
│ 中 → EN        qwen-mt-flash ⌄ │  方向 + 模型
├────────────────────────────────┤
│ 原文最多三行，超出省略…          │  灰色次要文字
├────────────────────────────────┤
│ 译文以流式逐字出现 ▌             │  主文字，可选中
├────────────────────────────────┤
│ 复制译文   换向   存为笔记    ✕  │  操作行
└────────────────────────────────┘
```

- 定位：鼠标位置偏移 `(+14, -14)`，超出屏幕边缘自动翻转 / 收进 `visibleFrame`。
- 关闭：`Esc` / 点击弹窗外 / 再次 `Option+Q` / 鼠标离开 6 秒后淡出（可配）。
- 视觉沿用主面板：深色底 `#050506`、圆角 12、`white.opacity(0.09)` 描边，与笔记面板统一。

### 5.4 设置入口

顶栏齿轮菜单与状态栏右键菜单内新增：

```
Translate Selected Text        等价于按下 ⌥Q
Translation Settings…          打开设置窗口
```

设置窗口（独立窗口，480×560）包含：API Key（Keychain 存储，可切换显示）、
模型选择（Balanced / Best quality / Fastest，附一句说明）、自动翻译开关、
划词翻译开关 + 快捷键选择（⌥Q / ⌥D / ⌥S / ⌃⌥T）、辅助功能权限状态与授权入口、Base URL。

## 六、分期计划

| 阶段 | 内容 | 状态 |
|---|---|---|
| **P0 地基** | 语言模型、请求模型、`TranslationService`、Keychain、设置存储 + 单元测试 | ✅ 已完成 |
| **P1 翻译页** | 顶栏双模式 tab、方向条、左右分栏、流式渲染、错误态 | ✅ 已完成 |
| **P2 划词** | 权限申请、`SelectionReader`、全局热键、弹窗面板与定位 | ✅ 已完成 |
| **P3 打磨** | 设置窗口、快捷键预设、存为笔记、弹窗自动收起 | ✅ 已完成，术语表待做 |

每个阶段结束跑 `swift test`，并新增：`TranslationLanguageTests`、`TranslationRequestTests`（请求体构造）、`TranslationStreamParserTests`（SSE 解析）、`SelectionTextNormalizerTests`（空白归一化 / 超长截断）。

## 七、风险清单

| 风险 | 影响 | 对策 |
|---|---|---|
| 辅助功能权限在 ad-hoc 签名下反复失效 | 划词功能开发期难调试 | 用打包后的 `.app` 测试；正式分发需 Developer ID |
| Electron 系应用取不到选中文本 | 划词失败 | 剪贴板兜底 + 明确错误提示 |
| `Option+Q` 与用户已有快捷键冲突 | 热键不生效 | 支持自定义快捷键 |
| 百炼接口限流 / 免费额度耗尽 | 翻译失败 | 请求去重、错误提示区分限流 |
| 弹窗抢焦点打断用户输入 | 体验灾难 | `.nonactivatingPanel` + 灰度验证 |
| API Key 泄露 | 账号风险 | Keychain + `.gitignore` 核查 |

## 八、已确认的实现决策（2026-10-01）

| 决策点 | 结论 |
|---|---|
| 触发方式 | **自动翻译**：输入停顿 600ms 触发，`⌘↩` 可强制立即执行 |
| 页面布局 | **左右分栏**：左侧输入、右侧结果；展开宽度统一为 700–760pt，笔记页与翻译页共用，切模式不伸缩 |
| 语言范围 | **只做中英**，`TranslationLanguage` 已按可扩展枚举设计，后续加语种无需改请求层 |
| 划词历史 | **不做**，保持弹窗轻量 |
| 存为笔记 | **做**。翻译页与划词弹窗都提供 `Save as note`，写入 `> 原文` + 译文 |
| API Key | **用户自行配置**，存 macOS Keychain，不落 UserDefaults |

## 九、实现清单（已完成）

新增 13 个文件：

| 文件 | 说明 |
|---|---|
| `Translation/TranslationLanguage.swift` | 语种枚举、方向映射、中英自动检测 |
| `Translation/TranslationAPI.swift` | 请求/响应模型、SSE 行解析、错误类型与文案 |
| `Translation/TranslationService.swift` | 流式（flash/lite）与一次性（plus）双通道 + HTTP 状态映射 |
| `Translation/KeychainStore.swift` | API Key 的 Keychain 读写 |
| `Translation/TranslationSettingsStore.swift` | Key / 模型 / Base URL / 自动翻译 / 划词开关 / 快捷键 |
| `Translation/TranslationSessionStore.swift` | 翻译页状态机：防抖、取消、流式追加、存为笔记 |
| `Selection/GlobalHotKey.swift` | Carbon 热键封装 + 快捷键预设 |
| `Selection/SelectionReader.swift` | 权限判定、AX 取词（超时 + 多候选 + range 兜底）、剪贴板两轮兜底与还原、文本归一化、失败诊断 |
| `Selection/TranslationPopupPanel.swift` | 非激活弹窗面板 |
| `Selection/SelectionTranslationController.swift` | 热键编排、加载态先出、弹窗定位、自动收起、事件监视 |
| `Views/TranslationView.swift` | 翻译页（左右分栏，输入区无滚动条） |
| `Views/TranslationPopupView.swift` | 划词弹窗内容与各状态（加载 / 结果 / 错误 + 失败诊断 / 权限引导） |
| `Views/HidesScrollIndicators.swift` | 关掉 `TextEditor` 底层 `NSScrollView` 的滚动条（SwiftUI 无此入口） |
| `Views/TranslationSettingsView.swift` + `Window.swift` | 设置窗口 |

改动 7 个既有文件：`AppServices.swift`（新增）、`WorkspaceMode.swift`（新增）、
`NotchGeometry.swift`（展开宽度改为只按屏幕计算，与模式解耦）、
`NotchPanelController.swift`（注入 services；因宽度恒定，已移除模式变更监听与相应的窗口重设）、
`NotebookView.swift`（顶栏双 tab + 内容切换）、`NoteStore.swift`（`addTab(text:)`）、
`AppDelegate.swift`（装配控制器与菜单）。

新增测试：`TranslationLanguageTests`、`TranslationRequestTests`、`TranslationStreamTests`
（SSE 解析 + 错误映射）、`SelectionTextNormalizerTests`、`SelectionRangeSlicerTests`
（UTF-16 选区切片，含 emoji 与越界）、`TranslationNoteComposerTests`、
`TranslationLayoutTests`。`swift test` 全绿，启动冒烟测试无崩溃。

## 十、后续可做（未实现）

1. **术语表 / 领域提示**：`translation_options` 已支持 `terms`、`domains`，可在设置里加词表。
2. **更多语种**：`TranslationLanguage` 补 `case` 即可，UI 需加语言下拉。
3. **快捷键录制**：目前是 4 个预设，尚未支持「按下即录制」的自定义方式。
4. **弹窗定位锚点**：目前用鼠标位置。键盘选词（Shift + 方向键）时鼠标可能在别处，弹窗会飘。
   可改为优先使用 AX 选区元素的 frame，取不到再退回鼠标位置。
