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
