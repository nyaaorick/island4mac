# 文件拖放功能测试指南

## 🚀 启动测试

### 1. 打开项目
```bash
open "/Users/applemima1111/Desktop/创作｜/Mac灵动岛/Mac灵动岛.xcodeproj"
```

### 2. 编译并运行
- 在 Xcode 中按 `Cmd + R` 运行项目
- 或使用菜单：Product → Run

## 🧪 测试步骤

### 测试 1: 基本拖拽检测
1. 启动应用后，灵动岛应该显示在屏幕顶部
2. 打开 Finder，选择任意文件
3. **开始拖拽** 但还不要接近刘海
4. ✅ 预期：什么都不会发生（这是正常的）
5. **继续拖拽接近屏幕顶部**
6. ✅ 预期：
   - 当鼠标进入刘海区域时，岛会**自动展开**
   - 自动切换到 **Files** 标签
   - 看到控制台输出：`🎯 Drag entered notch region`

### 测试 2: 视觉反馈检查
1. 继续上面的拖拽动作，将文件拖到展开的文件区域上方
2. ✅ 预期看到：
   - **蓝色虚线边框**（不是白色！）
   - 边框在 **呼吸**（opacity 0.10 ↔ 0.15）
   - 背景有**淡蓝色填充**
   - 图标变成**蓝色**并**放大**
   - 文字变成 `"Drop files here"` / `"Release to save"`

### 测试 3: 第一个文件测试
1. 确保文件区是**空的**（没有文件）
2. 从 Finder 拖拽一个文件
3. ✅ 预期：
   - 即使是第一个文件，也应该有完整的视觉反馈
   - **不需要**先放一个文件进去才能工作

### 测试 4: 拖拽退出
1. 拖拽文件进入刘海区域后，**不释放**
2. 将鼠标移出刘海区域
3. ✅ 预期：
   - 蓝色边框和填充**消失**
   - 图标和文字恢复正常
   - 看到控制台输出：`📤 Drag exited notch region`

### 测试 5: 实际放下文件
1. 拖拽文件到文件区
2. **释放鼠标**
3. ✅ 预期：
   - 文件被添加到列表
   - 显示文件图标和名称
   - 触觉反馈（如果开启）

### 测试 6: 多文件拖拽
1. 在 Finder 中选择**多个文件**
2. 一起拖拽到刘海
3. ✅ 预期：
   - 所有文件都能正确检测
   - 视觉反馈正常
   - 释放后所有文件都被添加

### 测试 7: 不同来源
测试从这些地方拖拽：
- ✅ Finder 窗口
- ✅ 桌面
- ✅ 其他应用（如浏览器下载文件）
- ✅ 文本编辑器中的文件

## 🎨 视觉效果检查清单

### 拖拽前（正常状态）
- [ ] 淡白色虚线边框 (opacity 0.12)
- [ ] 无背景填充
- [ ] 图标白色半透明
- [ ] 文字：`"Ready for Files"` / `"Drag files or click to browse"`

### 拖拽时（激活状态）
- [ ] **蓝色虚线边框** (accentColor, opacity 0.9)
- [ ] **蓝色背景填充** (呼吸动画)
- [ ] **蓝色图标** (渐变)
- [ ] 图标放大 1.15x
- [ ] 图标上移 2pt
- [ ] 文字变色为蓝色
- [ ] 文字内容改变

## 🐛 常见问题排查

### 问题 1: 拖拽没反应
**检查**：
- 控制台是否有 `🎯 Drag entered notch region` 输出？
  - 有 → 全局检测正常，问题在视觉层
  - 没有 → 检查 `DragDetectorManager` 是否启动

**解决**：
```swift
// 在 AppState.init() 中应该有这行：
setupGlobalDragDetector()

// 在 OverlayWindowController.reposition() 中应该有：
self?.appState.updateNotchRegion(frame)
```

### 问题 2: 边框还是白色
**检查**：
- `appState.isGlobalDragActive` 是否变为 `true`？
- `isTargeted` 是否变为 `true`？

**调试**：
在 `IslandFilesZone` 中添加：
```swift
.onChange(of: appState.isGlobalDragActive) { _, value in
    print("🔵 isGlobalDragActive:", value)
}
.onChange(of: isTargeted) { _, value in
    print("🎯 isTargeted:", value)
}
```

### 问题 3: 没有自动展开
**检查** `AppState.setupGlobalDragDetector()` 中的：
```swift
detector.onDragEntersNotchRegion = { [weak self] in
    Task { @MainActor in
        // 这里应该调用：
        self?.activateOverlay(reason: .dragDetected)
        self?.currentSection = .files
    }
}
```

### 问题 4: 刘海区域不正确
**解决**：
确保每次窗口移动/调整大小后都调用：
```swift
appState.updateNotchRegion(newFrame)
```

## 📊 调试输出参考

正常的控制台输出应该是：
```
🎯 Drag entered notch region
📤 Drag exited notch region
🎯 Drag entered notch region
Added to tray: example.txt
```

## 🎉 成功标准

所有这些都正常工作：
- ✅ 第一个文件可以拖放
- ✅ 蓝色虚线边框明显可见
- ✅ 背景呼吸动画流畅
- ✅ 图标和文字动态变化
- ✅ 自动展开到文件区
- ✅ 拖拽进入/退出都有反馈
- ✅ 多文件同时拖拽正常
- ✅ 不同来源的文件都能检测

## 🔧 需要帮助？

如果遇到问题：
1. 检查控制台输出
2. 确认 `DragDetectorManager.swift` 已添加到项目
3. 检查 Build Phases → Compile Sources 中是否包含新文件
4. Clean Build Folder (Cmd + Shift + K) 然后重新编译

祝测试顺利！🚀
