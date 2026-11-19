# iOSTweaksToolbox

iOS 玩机工具箱 —— 面向 **iPhone 16e / iOS 27.0.1 / 未越狱 / 个人开发者证书侧载**。

Swift + SwiftUI，模块化架构。所有系统级能力先做**真实权限探测**再显示，探测失败就显示失败，不伪造成功；模拟功能一律标明是模拟。

## 模块

| 优先级 | 模块 | 说明 |
|---|---|---|
| P0 | 配置编辑器 | Plist（XML/Binary）真实读写、类型转换、搜索、差异预览、保存前快照 |
| P0 | JSON 编辑器 | 格式化 / 压缩 / 校验 / 键值替换 / 带快照保存 |
| P0 | Hex 编辑器 | 真实二进制读取、分页、字节搜索、单字节改写、写前快照 |
| P0 | 配置方案中心 | 方案库、导入导出、差异对比 |
| P0 | 灵动岛工作室 | 位置 / 尺寸 / 圆角 / 展开态可交互模拟器 + 方案保存 |
| P0 | 显示分辨率实验室 | 读取真实屏幕参数，建立自定义显示方案（模拟） |
| P0 | AOD 实验室 | 生命周期事件记录、测试 A/B/C、配置差异、诊断报告导出 |
| P0 | 设备身份管理 | 按 App 独立记录目标设备身份（型号 / ProductType / 系统 / 屏幕），真实值对照 |
| P1 | 文件管理器 | 沙盒 / 工作区 / App Group / 用户授权目录，QuickLook 预览 |
| P1 | 备份与恢复 | SHA-256 校验、快照、恢复前再快照、工作区 ZIP 导出 |
| P1 | 设备信息 | 型号 / 系统 / 内存 / 存储 / 电池 / 温控 |
| P2 | 诊断与日志 | 事件时间线、日志导出、能力矩阵导出 |
| P2 | 能力矩阵 | 运行时探测每一项能力的真实可用性 |

## 能力边界

**公开 API 可实现**：设备信息、屏幕参数、自身沙盒文件管理、Plist/JSON/Hex 编辑、用户授权目录、App Group（需 entitlement）、方案保存、备份恢复、AOD 测试记录、灵动岛模拟器。

**需要额外授权**：特定 App Group 数据访问、受限容器读取、系统配置文件读取 —— 在「能力矩阵」里按运行时探测结果显示。

**普通未越狱 App 无法保证**：移动 SpringBoard 真实灵动岛、修改全局逻辑分辨率、修改系统 AOD 底层行为、修改锁屏触摸行为、写入受保护系统配置、获取 root。

工具不会把预览当成已生效，也不会声称这些能力已经具备。

## 沙盒越界技术背景（研究阶段结论）

`forcequitOS/worse_query` 在 iOS 26.0 – 27.3 beta 1 上可以拿到其他 App 容器的 sandbox extension：把自己 App Group 的 Library/Caches 换成指向目标的符号链接，再用 `container_query_*` + `sandbox_extension_consume` 兑现 token。前提是签名必须保留 `com.apple.security.application-groups` 权利。27.3 beta 2（24C5049d）起 Apple 修复。

版本窗口与构建判断集中在 `Experimental/OSCompatibility.swift`，后续可以把越界访问接进「配置编辑器」的受限路径 —— 但必须先通过能力探测，再显示可读写。

## 构建

```bash
xcodebuild -project iOSTweaksToolbox.xcodeproj \
           -scheme iOSTweaksToolbox \
           -sdk iphoneos -configuration Release \
           -derivedDataPath build \
           CODE_SIGNING_ALLOWED=NO build
```

或者直接用 Xcode 打开 `iOSTweaksToolbox.xcodeproj`，设置自己的 Team 与 Bundle Identifier 后运行。

GitHub Actions 会自动出未签名 IPA（`.github/workflows/build.yml`），下载后用你自己的证书重签。

## 数据落点

全部在 App 自己的沙盒内：

```
Documents/TweaksToolbox/
├── Profiles/{DynamicIsland,Display,AOD,Identity}/
├── Backups/            # 每次写入前的自动快照 + SHA-256 索引
├── Journals/           # AOD 事件、诊断报告、设备报告
├── Imports/            # 导入的配置文件副本
├── Snapshots/          # AOD 配置快照
└── backups-index.json
```

所有写入都带快照，恢复前再快照一次，写入失败立即回滚。

## 许可证

MIT，见 LICENSE。
