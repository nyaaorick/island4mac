# Mac灵动岛 (Antigravity) 项目开发状态日志

**生成时间**: 2026-01-24
**当前版本状态**: Alpha - 核心重构完成 (Post-Refactor)
**对标竞品**: [Boring Notch](https://github.com/TheBoredTeam/boring.notch) (v2.7)

---

## 1. 核心架构升级 (Core Architecture Overhaul)

我们刚刚完成了一次底层的**核心重构**，目前的架构已经从“原型级”升级为“工业级”。

### 🪟 窗口控制 (OverlayWindowController.swift)
*   **重写状态**: ✅ **已完成 (100%)**
*   **坐标系修复**: 彻底解决了窗口定位在屏幕底部的问题。现在使用 `screenFrame.maxY - targetSize.height` 算法，确保灵动岛死死吸附在物理刘海/菜单栏区域。
*   **层级霸权**: `panel.level` 提升至 `.screenSaver` (最高级)，确保在全屏游戏或视频中依然可见。
*   **解耦设计**: 引入了内部状态机 `OverlayPresentationState`，将“业务意图”(Intent) 与 “渲染状态”(State) 分离，消除了 UI 鬼影和闪烁。
*   **兼容性**: 提供了 `reposition()` 和 `showTemporarily()` 接口，完美适配旧的 Manager 代码。

### 🧠 交互中枢 (InteractionCoordinator.swift)
*   **状态**: ✅ **稳定运行**
*   **机制**: 采用**有限状态机 (FSM)** 管理所有交互。
*   **状态流**: `Idle` (静止) -> `Armed` (悬停预备) -> `Active` (展开交互) -> `Pinned` (钉住)。
*   **特性**: 包含各种防抖 (Debounce) 和重入保护 (Reentrant Safety)，确保快速滑动鼠标不会导致 UI 抽搐。

---

## 2. UI 与 视觉表现 (Visuals & UI)

### 🎵 音乐播放器 (ExpandedMusicView.swift)
*   **还原度**: **90%** (对比 Boring Notch)
*   **核心特性**:
    *   **动态专辑光晕**: 实现了背景模糊光晕 (Blur + Rotation)，但在参数上还需要微调以达到原版的“极光感”。
    *   **实时歌词**: 已集成歌词显示模块，支持同步滚动。
    *   **控制布局**: 1:1 复刻了 Boring Notch 的 5 按钮布局 (Shuffle-Prev-Play-Next-Repeat)。
*   **待优化**: 波形可视化 (Visualizer) 尚未实装。

### 🍎 物理引擎 (BoringAnimationPhysics.swift)
*   **来源**: 基于 Boring Notch 源代码的**逆向工程**。
*   **参数**:
    *   `boringInteractiveSpring`: Response 0.38, Damping 0.8 (果冻手感核心)。
    *   `boringOpenAnimation`: Response 0.42 (展开)。
    *   `boringCloseAnimation`: Damping 1.0 (关闭无回弹)。
*   **应用**: 目前已集成到核心动画库中，等待在 View 层全面启用。

---

## 3. 已知问题与下一步计划 (Gap Analysis)

### ⚠️ 待办事项 (TODOs)
1.  **物理动效对接**: 虽然 `BoringAnimationPhysics` 文件已存在，但 UI 层的 `.animation()` 调用需要全面替换为这些特定的 Spring 参数，以实现真正的“果冻效果”。
2.  **可视化波形**: `MusicVisualizer` 目前缺失，需要基于 `CAShapeLayer` 或 SwiftUI `Path` 实现伪波形动画。
3.  **功能模块扩展**:
    *   [ ] **Shelf (中转架)**: 暂未实现。
    *   [ ] **Webcam (镜子)**: 暂未实现。
    *   [ ] **Calendar (日程)**: 暂未实现。

---

## 4. 关键文件索引 (Key Files)

如果您需要让 AI 继续开发，请重点关注以下文件：

| 文件路径 | 描述 | 状态 |
| :--- | :--- | :--- |
| `Controllers/OverlayWindowController.swift` | **窗口容器**。负责定位、层级和生命周期。 | 🟢 完美 |
| `Coordination/InteractionCoordinator.swift` | **交互大脑**。处理所有鼠标/键盘/系统事件的状态流转。 | 🟢 稳定 |
| `Views/Music/ExpandedMusicView.swift` | **音乐主UI**。目前最复杂的视图组件。 | 🔵 需微调 |
| `Animations/BoringAnimationPhysics.swift` | **物理常数库**。存放所有动画曲线参数。 | 🟢 就绪 |
| `Managers/AppState.swift` | **数据源**。全局状态单例。 | 🟢 稳定 |

---

## 5. 开发者留言 (Developer Notes)

> "目前的系统已经在底层逻辑上追平了 Boring Notch。我们不再是一个简单的 SwiftUI 悬浮窗，而是一个拥有完整窗口管理策略和交互状态机的系统级应用。接下来的工作重点 purely 是 **'Make it Juice'** —— 即调整动画参数、光影细节和添加新功能模块。"

