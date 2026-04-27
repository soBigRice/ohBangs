# ohBangs 后续技术路径与实施手册

> 配套阅读：根目录 `MAC_NOTCH_DYNAMIC_ISLAND_PLAN.md`（产品总纲）。
> 本文档聚焦**接下来要做的事**：交互细化、状态机扩展、内容模块（含充电动画）、踩坑清单。

---

## 0. 当前进度快照

| 模块 | 状态 | 文件 |
|------|------|------|
| NSPanel 顶部贴合刘海 | ✅ | `IslandWindowManager.swift` |
| 真实硬件刘海形状（quad bezier shoulders） | ✅ | `IslandView.swift / NotchShape` |
| 收起 / 展开状态机 | ✅ | `IslandStateStore.swift` |
| 三档动画（collapsed → hint → expanded） | ✅（本次新增） | `IslandView.swift` |
| 内容 Provider 协议 | ⏳ | — |
| 充电动画卡片 | ⏳ | — |
| 自动收起 / 失焦收起 | ⏳ | — |
| 多屏 & 全屏适配 | ⏳ | — |

---

## 1. 交互三段式（Hover-to-hint, Click-to-expand）

### 1.1 状态机定义

```
            cursor enter            click
 ┌───────────┐ ────────►  ┌──────┐ ────────► ┌──────────┐
 │ collapsed │            │ hint │           │ expanded │
 └───────────┘ ◄────────  └──────┘ ◄──────── └──────────┘
            cursor leave          click  /  outside-click  /  ESC
```

- `collapsed`：纯硬件刘海尺寸（185×32），仅相机点
- `hint`：hover 预览态（210×38），轻微「呼吸」放大，提示「这是可交互的」
- `expanded`：完整通知卡片（360×96）

### 1.2 关键尺寸

| 状态 | 宽 | 高 | topR | bottomR |
|------|----|----|------|---------|
| collapsed | 185 | 32 | 6 | 12 |
| hint | 210 | 38 | 8 | 16 |
| expanded | 360 | 96 | 14 | 22 |

### 1.3 转换规则（已实装）

- 在 `collapsed` / `hint` 之间由 hover 自动切换
- 在 `expanded` 时 hover 不影响状态
- 点击：
  - `collapsed` / `hint` → `expanded`
  - `expanded` → 若仍 hover 则回到 `hint`，否则 `collapsed`

### 1.4 后续需补的交互

- [ ] **失焦自动收起**：监听 `NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown])`，落点不在 panel frame 内则 `collapse()`
- [ ] **ESC 收起**：在 `expanded` 状态时拦截键盘事件
- [ ] **超时自动收起**：进入 `expanded` 后启动 `Task.sleep(8s)`，期间无 hover 则收起；hover 期间 reset 计时器
- [ ] **快速连点防抖**：`displayState` 切换间隔 < 80ms 直接丢弃中间帧（用 `Combine.throttle`）

---

## 2. 内容模块系统（IslandContentProvider）

### 2.1 协议草案

```swift
@MainActor
protocol IslandContentProvider: AnyObject, Identifiable {
    var id: String { get }
    var priority: Int { get }                  // 数值越大越优先抢占展示
    var compactView: AnyView { get }           // 收起态右侧小图标
    var expandedView: AnyView { get }          // 展开态完整 UI
    var hintView: AnyView { get }              // hover 预览（默认 = compactView）

    var statePublisher: AnyPublisher<ProviderEvent, Never> { get }
    func start()
    func stop()
}

enum ProviderEvent {
    case appeared           // 数据源刚出现 → 触发"小弹一下"提示
    case updated            // 持续更新（如进度条）
    case disappeared        // 数据源消失 → 自动收起
}
```

### 2.2 调度策略

`IslandStateStore` 持有 `currentProvider: IslandContentProvider?`：

1. 多个 provider 并存时，按 `priority` 选最高
2. 新 provider 抢占 → 触发「叠层翻牌」动画（旧内容下沉、新内容从顶部滑入）
3. provider 消失 → 自动收起到 `collapsed`

### 2.3 计划接入的 Provider（按优先级从高到低）

| Provider | 优先级 | 触发时机 | 说明 |
|----------|--------|----------|------|
| `ChargingProvider` | 100 | 充电器插入 | 见 §3 充电动画 |
| `MusicProvider` | 80 | NowPlaying 有内容 | 通过 MediaRemote 私有 API 或公开的 MPNowPlayingInfoCenter |
| `TimerProvider` | 70 | 系统计时器/Pomodoro | 自定义 |
| `AirDropProvider` | 60 | AirDrop 接收 | 短期不做 |
| `IdleProvider` | 0 | 默认 fallback | 仅显示相机点 |

---

## 3. 充电动画卡片（重点模块）

### 3.1 数据源

使用 **IOKit 电源管理 API**（公开、无私有 API 风险）：

```swift
import IOKit.ps

// 获取电源信息
let blob = IOPSCopyPowerSourcesInfo().takeRetainedValue()
let sources = IOPSCopyPowerSourcesList(blob).takeRetainedValue() as Array

for source in sources {
    let info = IOPSGetPowerSourceDescription(blob, source).takeUnretainedValue() as! [String: Any]
    let isCharging   = info[kIOPSIsChargingKey] as? Bool ?? false
    let percentage   = info[kIOPSCurrentCapacityKey] as? Int ?? 0
    let powerSource  = info[kIOPSPowerSourceStateKey] as? String  // "AC Power" / "Battery Power"
    let timeToFull   = info[kIOPSTimeToFullChargeKey] as? Int     // 分钟
}
```

### 3.2 监听插拔事件

```swift
// 注册 RunLoop 回调（不使用 polling）
let runLoopSource = IOPSNotificationCreateRunLoopSource(
    { _ in
        Task { @MainActor in
            ChargingProvider.shared.refresh()
        }
    },
    nil
).takeRetainedValue()

CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
```

### 3.3 动画设计（三段式）

#### 阶段 A：插入瞬间（0–0.6s）

- 状态机：`collapsed` → 强制 `expanded`
- 视觉：
  - 左侧出现一个**充电图标**（`bolt.fill`），从 0.6 缩放 + 旋转 -15° 弹入
  - 周围一圈**绿色光晕**呼吸扩散一次（scale 0.8 → 1.4，opacity 0.6 → 0）
  - 右侧数字 `42%` 用 `contentTransition(.numericText())` 从 0 滚到当前值
- 触感：可调用 `NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)`

#### 阶段 B：持续显示（0.6s – 4s）

- 内容布局（展开态）：
  ```
  ┌──────────────────────────────────────────────┐
  │  ⚡  电池充电中            ████████░░  78%   │
  │      预计 32 分钟充满                          │
  └──────────────────────────────────────────────┘
  ```
- 进度条：`Capsule().fill(LinearGradient(green→mint))`，带**流光扫过**动画（每 1.6s 一次）
- 闪电图标：轻微脉冲 `scale 1 → 1.08`，duration 1.2s，autoreverse

#### 阶段 C：自动收起（4s 后）

- 退回到 `hint` 态（不是完全 `collapsed`）
- 收起后：相机点旁边显示一个**微型电池条**，长度 = 当前电量百分比
- 拔出充电器时，`hint` 态收回 `collapsed`，闪电图标用 fade-out 淡出

### 3.4 SwiftUI 实现要点

```swift
struct ChargingCardView: View {
    @ObservedObject var vm: ChargingViewModel
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.18))
                    .scaleEffect(pulse ? 1.4 : 0.9)
                    .opacity(pulse ? 0 : 0.7)
                    .animation(.easeOut(duration: 1.2).repeatForever(autoreverses: false),
                               value: pulse)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.green)
                    .scaleEffect(pulse ? 1.06 : 1.0)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                               value: pulse)
            }
            .frame(width: 42, height: 42)
            .onAppear { pulse = true }

            VStack(alignment: .leading, spacing: 4) {
                Text("电池充电中")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(vm.timeRemainingText)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(vm.percent)%")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                ProgressBar(value: Double(vm.percent) / 100)
                    .frame(width: 80, height: 4)
            }
        }
        .padding(.horizontal, 16)
    }
}
```

---

## 4. 动画系统统一规范

### 4.1 单一 spring 原则

所有形状几何动画**必须**使用同一条 spring，避免 driver 不一致造成抖动：

```swift
extension Animation {
    static let islandSpring = Animation
        .spring(response: 0.45, dampingFraction: 0.78, blendDuration: 0)
}
```

### 4.2 内容动画允许独立

- 文字、数字、icon 切换允许使用 `.easeOut` / `numericText` / `symbolEffect`
- 但**透明度切换必须延迟到形状基本到位**（约 0.08s 延迟）

### 4.3 动画中断规则

- `displayState` 变化 → 当前 spring 自动中断并从当前帧 spring 到新值（SwiftUI 默认行为）
- Provider 切换 → 在 store 里加 `inTransition` flag，期间忽略外部事件
- **不要**用 `withAnimation` 嵌套 `withAnimation`，会破坏 driver 一致性

---

## 5. 踩坑清单（已经踩过 + 预判会踩）

### ⚠️ 踩坑 1：NSPanel 跟着 SwiftUI resize → 动画割裂
**症状**：spring 还在弹，AppKit 已经把 window 切到目标尺寸，整体一卡一卡。
**解决**（已实施）：NSPanel 固定为最大尺寸 `IslandLayout.panelWidth × panelHeight`，所有动画在 SwiftUI 内部。

### ⚠️ 踩坑 2：`Shape` 不能用 `strokeBorder`
**症状**：编译报错 `value of type 'NotchShape' has no member 'strokeBorder'`。
**解决**：`strokeBorder` 是 `InsettableShape` 协议方法。要么实现 `inset(by:)`，要么用 `stroke`。

### ⚠️ 踩坑 3：透明面板被穿透 / 不被穿透
**症状**：透明区域响应了点击，或者刘海区域反而点不到。
**解决**：
- panel: `ignoresMouseEvents = false`（默认即此值）
- SwiftUI 顶层使用 `.contentShape(NotchShape(...))` 限定可命中区域
- 文字、图标加 `.allowsHitTesting(false)` 让点击穿透到底层 `onTapGesture`

### ⚠️ 踩坑 4：`screen.safeAreaInsets.top` 在外接显示器上为 0
**注意**：仅 MacBook 内置屏（且 macOS 12+）才有 `safeAreaInsets.top > 0`。
**解决**（已实施）：判断是否有真刘海，无则显示「仿刘海」（小 offset 与圆角保持一致）。

### ⚠️ 踩坑 5：`auxiliaryTopLeftArea` / `auxiliaryTopRightArea` 在某些机型为 nil
**解决**：用 `screenFrame.midX` 作为 fallback。

### ⚠️ 踩坑 6：进入全屏 App 后 panel 被遮住
**预判**：游戏 / 视频全屏会强制覆盖 statusBar 层。
**解决**：
- panel.level 用 `.statusBar` 或 `.popUpMenu`（更高）
- collectionBehavior 加 `.fullScreenAuxiliary`（已实施）
- 仍被遮挡时给用户开关，让他自己决定是否「全屏时隐藏」

### ⚠️ 踩坑 7：MediaRemote 私有 API 在 macOS 14+ 限制收紧
**预判**：`MRNowPlayingClient` 在新版会拿不到第三方 App 的播放信息。
**解决**：优先使用公开的 `MPNowPlayingInfoCenter.default()`，私有 API 仅作为补充，且要写降级。

### ⚠️ 踩坑 8：充电状态 polling vs 事件回调
**坑**：用 `Timer` 每秒 poll 会浪费电。
**解决**：必须用 `IOPSNotificationCreateRunLoopSource`，事件驱动。

### ⚠️ 踩坑 9：动画期间快速点击导致状态错乱
**预判**：`collapsed → expanded` 还在 spring 动画时再次点击，可能产生奇怪的中间帧。
**解决**：
- store 增加 `isAnimating: Bool`，在动画期间 toggle 触发的是「目标态翻转」而非「立即跳到下一态」
- 或对 `toggle()` 加 80ms throttle

### ⚠️ 踩坑 10：多个 NSScreen 时刘海可能不在主屏
**预判**：用户主屏可能是外接，MacBook 屏作为副屏。
**解决**：遍历所有 `NSScreen.screens`，找到 `safeAreaInsets.top > 0` 的那块（即真刘海屏），优先在那里显示。

### ⚠️ 踩坑 11：HiDPI 下 `quadCurve` 控制点的 0.5pt 偏差
**症状**：刘海与屏幕边缘衔接处出现 1px 缝隙。
**解决**：所有几何坐标对齐到 0.5 像素（`floor(x * 2) / 2`），或者将 panel y 起点稍微上推 0.5pt 让形状盖住边缘。

### ⚠️ 踩坑 12：暗黑模式与壁纸切换闪烁
**预判**：纯黑色填充在不同壁纸下偶尔显得不够黑（受系统色彩管理影响）。
**解决**：使用 `Color(NSColor.black)` 而非 `Color.black`，并把 colorScheme 锁定为 `.dark`。

---

## 6. 测试策略补充

### 6.1 单元测试

- `IslandStateStore`：所有状态转换路径（包括 hover + click 组合）
- `ChargingProvider`：mock IOKit 数据，验证百分比计算与时间格式化

### 6.2 视觉回归

- 每个状态截图 → 录入 `__Snapshots__`，用 `swift-snapshot-testing` 做像素级对比
- 重点：刘海与屏幕边缘的衔接处、hover 弹起的中间帧

### 6.3 手感测试 checklist

- [ ] hover 进入 → 弹起延迟 < 50ms，主观无卡顿
- [ ] hover 离开 → 收回有阻尼感，不是瞬切
- [ ] 连续点击 10 次 → 无错位、无闪烁
- [ ] 充电插入 → 0.3s 内有视觉响应
- [ ] 充电期间锁屏再解锁 → 动画状态恢复正确

---

## 7. 实施优先级（建议节奏）

```
Week 1
├─ ✅ Day 1-2  形状还原 + 单一 spring 动画
├─ ✅ Day 3    三档状态机（hover hint）
└─    Day 4-5  Provider 协议骨架 + IdleProvider

Week 2
├─ Day 6-7  ChargingProvider（数据 + 动画）
├─ Day 8    自动收起 / ESC / 失焦收起
└─ Day 9-10 多屏 / 全屏边界场景

Week 3
├─ Day 11-12 MusicProvider（NowPlaying）
├─ Day 13    Provider 切换的「翻牌」动画
└─ Day 14    设置面板 + 开机启动
```

---

## 8. 文件结构（目标）

```
ohBangs/
├── App/
│   ├── ohBangsApp.swift
│   └── AppDelegate.swift
├── Window/
│   └── IslandWindowManager.swift
├── State/
│   ├── IslandStateStore.swift
│   └── IslandLayout.swift
├── View/
│   ├── IslandView.swift
│   ├── NotchShape.swift
│   └── Cards/
│       ├── IdleCard.swift
│       ├── ChargingCard.swift
│       └── MusicCard.swift
└── Providers/
    ├── IslandContentProvider.swift
    ├── ChargingProvider.swift
    └── MusicProvider.swift
```

> 当前所有逻辑都在单文件里，到 Phase 2 再拆分。
