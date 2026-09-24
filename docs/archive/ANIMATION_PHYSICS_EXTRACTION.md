# 🎯 Boring.notch 动画物理参数提取报告

> **状态**: 完成
> **日期**: 2026-01-24
> **类型**: 帧精确逆向工程

---

## 📊 核心动画参数提取总结

### 1. 主要弹簧动画 (Core Springs)

| 动画名称 | Response | Damping | Blend | 源文件位置 | 用途 |
|---------|----------|---------|-------|-----------|------|
| **interactiveSpring** | 0.38 | 0.8 | 0 | `ContentView.swift:41` | 所有手势驱动的动画 |
| **openAnimation** | 0.42 | 0.8 | 0 | `ContentView.swift:123` | 灵动岛展开 |
| **closeAnimation** | 0.45 | 1.0 | 0 | `ContentView.swift:124` | 灵动岛收起（无回弹） |
| **primaryAnimation** | bouncy(0.4) | - | - | `drop.swift:21` | macOS 14+ 主动画 |

### 2. 组件特定弹簧 (Component Springs)

| 动画名称 | Response | Damping | 源文件位置 | 用途 |
|---------|----------|---------|-----------|------|
| **sliderDragSpring** | 0.35 | 0.7 | `NotchHomeView.swift:575` | 滑块拖拽反馈 |
| **buttonBounceSpring** | 0.3 | 0.3 | `Button+Bouncing.swift:24` | 按钮弹跳效果 |
| **hoverSelectionSpring** | 0.3 | 0.6 | `MusicControllerSelectionView.swift:88` | 悬停选择状态 |
| **dropZoneSpring** | 0.36 | 0.7 | `FileShareView.swift:84` | 拖放目标反馈 |

### 3. 平滑/缓动动画 (Smooth/Ease)

| 动画名称 | 类型 | 持续时间 | 源文件位置 | 用途 |
|---------|------|---------|-----------|------|
| **smooth** | .smooth | - | 多处 | 通用状态变化 |
| **smoothDuration** | .smooth | 0.3s | `SystemEventIndicatorModifier.swift:136` | 系统事件指示器 |
| **fastEaseInOut** | .easeInOut | 0.12s | `NotchHomeView.swift:342` | 快速切换 |
| **mediumEaseInOut** | .easeInOut | 0.2s | `NotchHomeView.swift:385` | 控制切换 |
| **onboardingEase** | .easeInOut | 0.6s | `OnboardingView.swift:33` | 引导步骤过渡 |

---

## 🧮 手势物理公式

### gestureProgress 计算
```swift
// Source: ContentView.swift line 569
gestureProgress = (translation / Defaults[.gestureSensitivity]) * 20
```

### gestureScale 计算
```swift
// Source: ContentView.swift lines 85-88
func gestureScale(from progress: CGFloat) -> CGFloat {
    guard progress != 0 else { return 1.0 }
    let scaleFactor = 1.0 + progress * 0.01
    return max(0.6, scaleFactor)
}
```

### gestureOpacity 计算
```swift
// Source: ContentView.swift line 296
func gestureOpacity(from progress: CGFloat) -> CGFloat {
    guard progress != 0 else { return 1.0 }
    return 1.0 - min(abs(progress) * 0.1, 0.3)
}
```

---

## 📐 圆角半径参数

```swift
// Source: sizing/matters.swift line 18
let cornerRadiusInsets = (
    opened: (top: 19, bottom: 24),
    closed: (top: 6, bottom: 14)
)

// 专辑封面圆角
// Source: sizing/matters.swift lines 20-23
let MusicPlayerImageSizes.cornerRadiusInset = (opened: 13.0, closed: 4.0)
```

---

## 🔄 手势处理流程

### 向下滑动打开 (handleDownGesture)
```
Source: ContentView.swift lines 560-580

1. 检查当前状态是否为关闭
2. 如果手势结束 (phase == .ended):
   - withAnimation(animationSpring) { gestureProgress = .zero }
   - return
3. 计算进度: gestureProgress = (translation / sensitivity) * 20
4. withAnimation(animationSpring) 应用进度
5. 如果 translation > sensitivity:
   - 触发触觉反馈
   - 重置 gestureProgress = .zero
   - doOpen()
```

### 向上滑动关闭 (handleUpGesture)
```
Source: ContentView.swift lines 583-608

1. 检查当前状态是否为展开
2. 计算负向进度: gestureProgress = (translation / sensitivity) * -20
3. withAnimation(animationSpring) 应用进度
4. 如果手势结束:
   - withAnimation(animationSpring) { gestureProgress = .zero }
5. 如果 translation > sensitivity:
   - 重置 gestureProgress
   - 触发触觉反馈
   - close()
```

### 悬停处理 (handleHover)
```
Source: ContentView.swift lines 511-555

进入悬停:
1. 取消之前的 hoverTask
2. withAnimation(animationSpring) { isHovering = true }
3. 如果关闭状态，触发触觉反馈
4. 如果未展开且启用悬停打开:
   - 等待 minimumHoverDuration 秒
   - 检查仍在悬停且未展开
   - doOpen()

离开悬停:
1. 等待 100ms 防抖动
2. withAnimation(animationSpring) { isHovering = false }
3. 如果展开状态，自动关闭
```

---

## 🧲 PanGesture 实现细节

```swift
// Source: PanGesture.swift

关键参数:
- threshold: 4 (默认触发阈值)
- noiseThreshold: 0.2 (过滤微小移动)
- axisDominanceFactor: 1.5 (轴向主导因子)
- endTimeout: 300ms (手势结束检测超时)
- mouseWheelScale: 8 (鼠标滚轮缩放因子)

核心逻辑:
1. DragGesture + NSEvent scrollWheel 双重支持
2. 轴向主导检查防止对角移动误触发
3. 累积值计算实现平滑跟随
4. 300ms 超时确保手势正确结束
```

---

## 📁 已更新的文件

### 新建文件
1. **`Animations/BoringAnimationPhysics.swift`**
   - 完整的动画物理库
   - 包含所有提取的弹簧参数
   - PanGesture 扩展和 ScrollMonitor

### 更新文件
1. **`Utilities/AnimationPresets.swift`**
   - 更新为精确的 Boring.notch 参数
   - 添加源码引用注释
   - 添加手势物理计算函数

2. **`Views/DynamicIslandView.swift`**
   - 手势处理函数使用 interactiveSpring
   - 悬停处理匹配原版逻辑
   - 添加自动关闭行为

---

## ✅ 实现检查清单

- [x] 提取核心 interactiveSpring 参数 (0.38, 0.8, 0)
- [x] 提取 openAnimation 参数 (0.42, 0.8, 0)
- [x] 提取 closeAnimation 参数 (0.45, 1.0, 0)
- [x] 实现 gestureProgress 物理公式
- [x] 实现 gestureScale 计算
- [x] 实现 gestureOpacity 计算
- [x] 更新 handleDownGesture 逻辑
- [x] 更新 handleUpGesture 逻辑
- [x] 更新 HandleHover 逻辑
- [x] 添加 PanGesture 扩展
- [x] 添加 ScrollMonitor 支持
- [x] 提取圆角半径参数
- [x] 提取组件特定弹簧参数

---

## 🎬 动画效果说明

### 为什么这些参数能创造"磁吸"感？

1. **response: 0.38** - 足够快速响应手指，但不会太突兀
2. **dampingFraction: 0.8** - 轻微欠阻尼创造生动感，但不会过度弹跳
3. **blendDuration: 0** - 动画立即响应，无混合延迟

### 为什么关闭动画使用 dampingFraction: 1.0？

临界阻尼 (1.0) 确保收起动作:
- 没有反弹/振荡
- 优雅地"落回"到关闭状态
- 给用户"结束"的明确反馈

### 为什么 buttonBounceSpring 使用 dampingFraction: 0.3？

极低阻尼创造:
- 明显的弹跳效果
- 游戏般的触感反馈
- 增加交互趣味性

---

## 📝 使用指南

```swift
// 打开灵动岛
withAnimation(IslandAnimations.interactiveSpring) {
    appState.activateOverlay(reason: .userExpanded)
}

// 关闭灵动岛
withAnimation(IslandAnimations.closeAnimation) {
    appState.deactivateOverlay()
}

// 手势进度更新
withAnimation(IslandAnimations.interactiveSpring) {
    gestureProgress = (translation / sensitivity) * IslandAnimations.gestureProgressMultiplier
}

// 计算缩放
let scale = IslandAnimations.gestureScale(from: gestureProgress)

// 悬停状态
withAnimation(IslandAnimations.interactiveSpring) {
    isHovering = true/false
}
```

---

> **注意**: 所有参数均从 Boring.notch 源代码直接提取，确保 1:1 帧精确复刻。
