# 真实修改能力：对照 Erosion 的实现

参考对象：Erosion_v1.0.5_Bilingual.ipa（v1.0.5，build 30，iOS 27.2 SDK，MinimumOSVersion 26.0），
与 QAQqaz/erosion-cn 的源码。

## 1. Erosion 到底靠什么做到"真实修改"

拆开它的二进制和源码，只有一条链路：

```
App Group 容器的 Library/Caches 换成指向目标的 symlink
        ↓
containermanagerd 发 sandbox token → sandbox_extension_consume 拿到句柄
        ↓
进程现在能读写 systemgroup.com.apple.mobilegestaltcache/.../com.apple.MobileGestalt.plist
        ↓
原位改写这份 plist 的 CacheExtra 字典 → 重启后系统读新值
```

关键点：它改的不是"某个开关"，而是 iOS 用来回答"这台设备支持什么"的那份缓存。
灵动岛、AOD、轻点唤醒、Apple 智能、地区、监管型号，全在同一份 plist 的 CacheExtra 里。

二进制里能验证：MobileGestalt 出现 53 次、container 205 次、sandbox 11 次、dlopen 2 次，
以及 sandbox_extension_consume 这套 container manager 调用序列。

## 2. 我们工程现在的状态

已移植并通过 CI 编译：Exploits/worse_query.{h,m}、Exploits/pathleak.{h,m}、桥接头、entitlements。

与原版相比，实现上补了三处，让它更耐操：

| 环节 | 上游 worse_query | 我们的实现 |
|---|---|---|
| Caches 处理 | removeItem + createDirectory，会删掉别人的 Caches 内容 | rename 到 .wq-caches-saved，结束再 rename 回来 |
| 并发 | 无保护 | flock(LOCK_EX) 串行化 |
| 失败路径 | 部分分支直接 return，symlink 残留 | 所有分支统一 wq_restore |

写入协议照抄 Erosion-CN 加固后的版本（真机踩出来的）：pwrite 原位覆盖 → 按需 ftruncate
→ F_FULLFSYNC → 读回逐字节校验 → 失败原位回滚。不先 ftruncate(fd, 0)，就是为了不制造零字节窗口。

## 3. 关于白苹果：真正的风险在哪

Erosion-CN 的 README 自己列了一串"会导致白苹果循环"的项：

- zHeENZu+wbg7PUprwNwBWg（RegionInfo）—— iOS 27 上是非缓存键，塞进 CacheExtra 会触发开机缓存合法性校验失败，整包重置
- uKc7FPnEO++lVhHWHFlGbQ（iPad 模式）+ 台前调度 —— 原文：「切勿关闭『在台前调度中显示程序坞』，否则会导致设备软砖（白苹果循环）」
- 0L5PkT61qoH1b/B1USWqjQ（RegionalBehaviorChinaBrick）—— 非缓存硬件键，写入触发开机重置
- gD8SNRcHQeIxCAvsp+2vjA / 91LyMcx4z1w3SGVeqteMnA —— 基带/WiFi 射频校准，动了两网直接废
- green-tea / not-green-tea / wapi —— 在 CacheData 二进制槽位里，不在 CacheExtra，塞错位置就是结构损坏

所以我把这 16 个键做成了硬编码黑名单：GestaltService.blockedKeys，编辑页标红禁用，
写入前 checkEdits 二次拦截。这不是文案提醒，是代码级拒绝。

## 4. 老实说，还剩哪些做不到

1. CacheData 二进制槽位（green-tea / not-green-tea / wapi）需要运行时从
   /usr/lib/libMobileGestalt.dylib 扫描述符表算出偏移。Erosion-CN 用 MGCacheLayout.swift
   实现了（扫 64 字节描述符：+0x00 键指针、+0x3A Int16 槽位号、+0x3C 类型）。这块还没移植，
   需要完整的 Mach-O 段解析，是独立的一大块。
2. iPad 模式 / 台前调度：技术上能写，但上游自己标注软砖风险，保持黑名单。
3. 逐 App 设备型号伪装：没有任何一条路径能做。Erosion 改的是全局 MobileGestalt，
   系统里所有 App 读到的都变；要按 App 隔离必须有注入能力（越狱或 LiveContainer 那种容器化运行），
   未越狱普通签名做不到。

## 5. "模仿并超越"可以落在哪

模仿：worse_query 已移植并编译通过，MobileGestalt 读写链路已经通了。

超越可以是这几件事，都不需要额外特权：

- 写完自动 diff 存档：每次应用带完整 before/after 键值快照 + SHA-256，可一键回到任意历史版本
- 开机前自检：写入前模拟系统校验（CacheExtra 键是否全为缓存键、CacheData 长度是否等于槽位×9、
  CacheUUID 是否匹配本机），不通过直接拒绝；Erosion 是写后读回才发现问题，我们写前就拦
- 机型参数库：把 ProductType / 监管型号 / ArtworkSubtype / 屏幕参数做成结构化表，
  改机型时一次性同步全部关联字段，而不是让用户逐个手改
- 配置差异地图：把「识别不同 iOS 版本的配置差异」真正落到 Gestalt 键级别
