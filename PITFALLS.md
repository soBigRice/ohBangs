# 开发踩坑记录 / Pitfalls

记录开发过程中遇到的非显然问题、根因与修法。新坑请追加到末尾，不要重写历史条目。

---

## 1. NSPanel + SwiftUI：Update Constraints 死循环崩溃

### 现象
启动后立即抛 `NSGenericException`：

```
The window has been marked as needing another Update Constraints in Window pass,
but it has already had more Update Constraints in Window passes than there are
views in the window.
<NSPanel: 0x...> {{663, 950}, {185, 32}}
```

堆栈关键帧：
```
NSHostingView.requestUpdate(after:)
ViewGraph.invalidateTransform()
-[NSWindow _postWindowNeedsUpdateConstraints]
```

### 根因
两条尺寸权威同时存在，互相 invalidate：

1. `NSHostingController` 装入 `panel.contentViewController`，走 AutoLayout，会把 SwiftUI 的"理想尺寸"反推给 NSPanel。
2. `IslandWindowManager` 在 `displayState` 变化时主动 `panel.setFrame(...)` 切尺寸（185×32 / 270×50 / 720×192）。
3. SwiftUI 内层视图又用 `.frame(width: width, height: height)` 显式声明每个状态的尺寸。

三者在同一 CATransaction 里反复触发 `setNeedsUpdateConstraints`，AppKit 检测到约束更新次数 > 视图数 即抛异常。

### 修法
**让 panel.frame 成为尺寸的唯一来源**，关掉 SwiftUI 这条 AutoLayout 反推路径：

- `IslandWindowManager`：用 `NSHostingView` + `panel.contentView`，开 `autoresizingMask = [.width, .height]` 并 `translatesAutoresizingMaskIntoConstraints = true`。**不要**用 `NSHostingController` + `contentViewController`。
- `IslandView` 根节点：用 `.frame(maxWidth: .infinity, maxHeight: .infinity)` 撑满 hosting，**不要**写死 `.frame(width:height:)`。
- macOS 13+ 同时设置 `hostingView.sizingOptions = []`，禁止 SwiftUI 驱动 window 尺寸。

### 教训
- SwiftUI 嵌在 AppKit 自定义窗口里时，**只能有一个尺寸权威**。要么 SwiftUI 主导（`sizingOptions = [.preferredContentSize]`，让 window 跟着内容变），要么 AppKit 主导（hostingView 撑满，SwiftUI 不主张尺寸）。混用必崩。
- 涉及自定义 NSPanel 形状/位置的场景，**永远选 AppKit 主导**——尺寸由你 `setFrame` 控制，hosting 只负责画。
- 这个异常**不一定每次都触发**，依赖动画时序。Debug 跑得过不代表 Release 没事。

---

## 2. NSPanel + SwiftUI：透明区域热区不透传，挡住下层窗口

### 现象
Island 收回 collapsed 形状后，肉眼看不见的"曾经展开过"的大区域（≈720×192）仍然吃掉鼠标点击：下层窗口（Finder、菜单、Dock 等）在这个矩形内点不动。视觉上 island 已经缩小，但热区没跟着缩。

### 根因
panel 的 frame 是固定的最大尺寸（panelWidth × panelHeight，覆盖 expanded 形状外加 padding），SwiftUI 内层虽然用 `.contentShape(NotchShape(...))` 把命中区域限制成了当前 island 形状，但 `IslandView` 根 `ZStack` 里塞了一层 `Color.clear` 当背景：

```swift
ZStack(alignment: .top) {
    Color.clear           // ← 这货充满 panelWidth × panelHeight
    ZStack { ... }
        .contentShape(NotchShape(...))  // 内层正确限制了热区
        .onHover { ... }
        .onTapGesture { ... }
}
```

`Color.clear` 在 SwiftUI 默认参与 hit testing：它撑满整个 panel，于是 panel 大区域的鼠标事件全部被它吃掉，NSHostingView.hitTest 返回的是这个 Color.clear，事件不会透传给下层窗口。内层的 `.contentShape` 只决定 onHover/onTapGesture 怎么响应，**不会**让外面那张 clear 变得"透明可穿"。

### 修法
**直接删掉根 ZStack 里的 `Color.clear`**。NSPanel 已经 `isOpaque = false` + `backgroundColor = .clear`，当 SwiftUI 命中测试在 island 形状外返回 nil，NSHostingView.hitTest 也跟着返回 nil，AppKit 自动把事件透传到下层窗口。外层 `.frame(width: panelWidth, height: panelHeight, alignment: .top)` 仍然把 island 对齐到 hosting 顶部，不需要 Color.clear 来"占位"——frame 是布局尺寸，不是命中区域。

### 教训
- **看不见 ≠ 不挡事件**。SwiftUI 中 `Color.clear` 默认是 hit-testable 的，要么 `.allowsHitTesting(false)`，要么干脆别放。
- NSPanel + NSHostingView 的事件透传链：`NSWindow → contentView(NSHostingView).hitTest → SwiftUI hit test`。任一环节返回非 nil，事件就被这个 panel 截胡，下层窗口收不到。所以"看不见的热区"问题，**必须把 SwiftUI 这一层的命中区域和视觉区域严格对齐**——`.contentShape` 只对它所在的子树生效，外层兄弟视图（如背景 Color）要单独处理。
- 决定用"固定大 panel + SwiftUI 内层动画缩放"这种架构（理由见 Pitfall #1：尺寸权威只能有一个），就要承担一个隐形责任：**panel 内任何 hit-testable 的视图，其形状必须和当前可见 island 形状一致**，否则就会出现"看不见但挡事件"的鬼区。

---

## 3. macOS App 图标：只看 asset catalog 编译成功不够

### 现象
`Assets.xcassets/AppIcon.appiconset` 里有图标 PNG，`xcodebuild` 也能生成 `AppIcon.icns`，但实际从 Xcode/DerivedData 启动后 Dock/Finder 仍可能显示通用白图标。

### 根因
这次同时踩了两个点：

1. 只验证了临时 `.derivedData` 构建产物，没有确认 Xcode 默认 DerivedData 里实际启动的 `.app`。
2. 仅依赖 asset catalog 自动生成的 `AppIcon.icns` 时，产物里的 `.icns` 不完整，`iconutil` 解包只看到部分尺寸；同时生成脚本里的渐变描边实现用了 `addClip()` 直接裁整块圆角矩形，导致胶囊边框被画成大面积浅色填充。

### 修法
图标链路要按 macOS 真实加载路径验证：

- 用 `iconutil -c icns` 从完整 10 尺寸 `.iconset` 生成 `ohBangs/AppIcon.icns`。
- 在 target build settings 里明确设置 `INFOPLIST_KEY_CFBundleIconFile = AppIcon.icns`，并移除 `ASSETCATALOG_COMPILER_APPICON_NAME`，避免 asset catalog 自动产物覆盖手工 `.icns`。
- 构建默认 DerivedData 后检查：
  - `Contents/Info.plist` 的 `CFBundleIconFile`
  - `Contents/Resources/AppIcon.icns` 文件大小和 SHA
  - `iconutil -c iconset` 是否能解出 10 个标准尺寸
  - `NSWorkspace.shared.icon(forFile:)` 导出的图标是否是自定义图
- 最后重注册 bundle 并刷新缓存：`lsregister -f -R -trusted <app>`、`qlmanage -r cache`、必要时重启 Dock。

### 教训
- App 图标问题不能只看 Xcode 构建成功；必须验证系统 API 实际取到的图标。
- macOS Dock/Finder 会缓存 bundle 图标。图标文件已经变了，不代表当前运行进程或 Dock 立刻刷新。
- 画渐变描边时不能把整块圆角矩形 `addClip()` 后直接绘制渐变；要构造外圆角与内圆角的环形区域，只裁剪描边区域。
