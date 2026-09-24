# 剪贴板记忆 - 最终交付文档

## 一、交互模型描述

### 问题定义
macOS 会忘记刚复制的内容。

### 解决方案
灵动岛短暂记忆、温和提醒、然后退出视线。

### 四态交互

**1. 静默态**
- 默认状态
- 无可见 UI
- 零注意力成本

**2. 复制确认态**
- 触发条件:检测到剪贴板变化
- 表现:岛屿显示"已复制"+预览
- 持续时间:约 1 秒
- 动效:无弹跳,仅温和落定

**3. 意图窥视态**
- 触发条件:复制后 2 秒内点击岛屿或按 ⌥⌘V
- 表现:展开显示最近 2-3 项
- 无标题栏,无滚动
- 选择后自动收起

**4. 专注回溯态**
- 触发条件:复制 2 秒后按 ⌥⌘V 或点击菜单项
- 表现:展开显示 6-8 项,可滚动
- 显示"剪贴板"标题 + 固定/清空按钮
- 可固定保持打开

---

## 二、状态转换图

```
静默 ──(剪贴板变化)──→ 复制确认 ──(~1秒)──→ 静默
 ↑                           │
 │                           │(2秒内点击/⌥⌘V)
 │                           ↓
 │                      意图窥视(2-3项)
 │                           │
 │                           │(选择项目/自动收起)
 │                           ↓
 └───────────────────────────┘

静默 ──(2秒后⌥⌘V/菜单)──→ 专注回溯(6-8项) ──(选择/关闭)──→ 静默
```

---

## 三、代码更新清单

### 1. ClipboardHistoryStore.swift (Services/)
**新增内容**:
- `PickerMode` 枚举:`.intentPeek` / `.focusedRecall`
- `ClipboardItem.ItemType`:新增 `.code` 类型
- `normalizedContent`:URL 去追踪参数逻辑
- `preview`:智能预览(去换行、50字符截断)
- `isInIntentWindow`:判断是否在 2 秒意图窗口内
- `showPickerExplicit(mode:)`:强制指定模式

**修改内容**:
- 过期时间:5分钟 → 24小时
- 去重逻辑:语义级去重(相同 URL 去参后视为相同)
- Toast 时长:1.2秒 → 1.0秒
- displayableItems:根据 mode 返回 3 项或 8 项
- 所有日志用 `#if DEBUG` 包裹

---

### 2. ClipboardMonitor.swift (Services/)
**修改内容**:
- 轮询间隔:0.4秒 → 0.5秒
- 过期检查:每次 → 每 10 次(约 5 秒)
- 新增代码检测:通过括号/关键词启发式判断
- 移除 `lastCopyTime` 成员(不需要)
- 所有日志用 `#if DEBUG` 包裹

---

### 3. ClipboardIslandViews.swift (Views/)
**ClipboardToastView**:
- 图标改用 `item.icon`(动态)
- 降低对比度:0.75 → 0.70, 0.45 → 0.40
- 注释:无动画,仅落定

**ClipboardPickerView**:
- 新增 `isIntentPeek` 判断
- 意图窥视:无标题,无滚动,2-3项
- 专注回溯:标题"剪贴板"(非"历史"),6-8项,可滚动
- 动画:0.25秒 ease-out,无弹跳

**ClipboardItemRow**:
- 新增 `isRecent` 参数
- 最近项:中等字重 + 0.75 不透明度
- 旧项目:常规字重 + 0.55 不透明度
- 代码类型:等宽字体
- 悬停:0.12秒 ease-out

---

### 4. NotchOverlayView.swift (Views/)
**修改**:
- `compactContent`:优先级 1 = 剪贴板 Toast
- Toast 可点击,触发 `showPicker()` + `.clipboardHistory` 原因
- `expandedContent`:如果 `isShowingPicker` 则显示 `ClipboardPickerView`

---

### 5. StatusBarController.swift ( Controllers/)
**修改**:
- `onShowClipboardHistory`:调用 `showPickerExplicit(mode: .focusedRecall)`
- `onClearClipboardHistory`:调用 `clearAll()`
- 所有日志用 `#if DEBUG` 包裹

---

### 6. HotKeyManager.swift (Managers/)
**新增**:
- `clipboardMonitor` 监听器
- `handleClipboardHotkey()`:触发专注回溯
- ⌥⌘V 热键(keyCode 9)
- 更新注释说明 3 个热键

---

### 7. OverlayVisibilityReason.swift (State/)
**新增**:
- `.clipboardHistory` case
- `shouldAutoHide`:排除 `.clipboardHistory`

---

### 8. AppState.swift (State/)
**新增**:
- `let clipboardHistory = ClipboardHistoryStore()`

---

### 9. AppDelegate.swift
**新增**:
- `private var clipboardMonitor: ClipboardMonitor!`
- 启动/停止 monitor

---

### 10. OverlayWindowController.swift ( Controllers/)
**新增**:
- `.environmentObject(appState.clipboardHistory)`

---

## 四、新增辅助方法和数据结构

### ClipboardItem.normalizedContent
```swift
var normalizedContent: String {
    var normalized = content.trimmingCharacters(in: .whitespacesAndNewlines)
    
    // URL 去追踪参数
    if type == .url, let url = URL(string: normalized) {
        if var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems = components.queryItems?.filter { item in
                let trackingParams = ["utm_source", "utm_medium", "utm_campaign", 
                                      "utm_term", "utm_content", "fbclid", "gclid"]
                return !trackingParams.contains(item.name.lowercased())
            }
            if let cleanedURL = components.url {
                normalized = cleanedURL.absoluteString
            }
        }
    }
    
    return normalized
}
```

### ClipboardItem.preview
```swift
var preview: String {
    let cleaned = content
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\r", with: " ")
        .replacingOccurrences(of: "\t", with: " ")
        .replacingOccurrences(of: "  ", with: " ")
        .trimmingCharacters(in: .whitespaces)
    
    let maxLength = 50
    if cleaned.count > maxLength {
        return String(cleaned.prefix(maxLength)) + "…"
    }
    return cleaned
}
```

### 代码检测启发式
```swift
let codeIndicators = ["{", "}", "[", "]", ";", "function", "def ", 
                      "class ", "import", "const ", "let ", "var "]
if codeIndicators.contains(where: { trimmed.contains($0) }) {
    return (trimmed, .code)
}
```

---

## 五、最终检查清单

### 交互流程
- [ ] 复制 → 确认 → 消失(1秒内完成)
- [ ] 确认期间点击 → 意图窥视(2-3项)
- [ ] ⌥⌘V → 专注回溯(6-8项)
- [ ] 菜单"打开剪贴板历史" → 专注回溯

### 感知测试
- [ ] 感觉冷静,无注意力劫持
- [ ] 感觉原生,非第三方功能
- [ ] 感觉完成,无"半成品"感
- [ ] 展开像"内容浮现",非"UI打开"
- [ ] 收起感觉必然,非主动触发

### 性能验证
- [ ] CPU 空闲 < 0.5%(Activity Monitor)
- [ ] 无控制台日志(Release 构建)
- [ ] 轮询间隔 0.5 秒
- [ ] 24 小时静默过期

### 智能验证
- [ ] 相同内容去重(仅更新时间戳)
- [ ] URL 去追踪参数(`utm_*`, `fbclid`)
- [ ] 代码检测(等宽预览)

### 菜单与热键
- [ ] ⌥⌘V 热键生效
- [ ] 菜单项"打开剪贴板历史"生效
- [ ] 菜单项"清空剪贴板历史"生效
- [ ] 所有菜单项始终可用(不变灰)

---

## 六、质量标准

### ✅ 通过标准
如果用户说:"我没注意到它,直到它救了我一次"
→ **成功**

如果用户说:"这个剪贴板管理器真不错!"
→ **失败**

### 设计原则
1. 减法优于加法
2. 平静即信心
3. 柔和非模糊
4. 一致物理逻辑
5. 不可见的决策

### 哲学对齐
- 这不是功能,是能力补偿
- 用户忘记它存在 = 设计成功
- 用户想配置它 = 设计失败
- 感觉像 macOS 遗漏的部分 = 完美

---

## 七、测试文档

详细测试清单见:
- `CLIPBOARD_REFINED_CHECKLIST.md` (完整功能测试)
- `CLIPBOARD_REFINEMENT_SUMMARY.md` (技术实现总结)

---

## 签署

**产品定义**: macOS 忘记我刚复制的内容。  
**解决方案**: 灵动岛短暂记忆、温和提醒、然后退出视线。  
**质量标准**: "一个被遗漏的 macOS 能力,被温和修复。"

---

完成日期: 2026-01-12  
状态: 代码完成,等待测试验证
