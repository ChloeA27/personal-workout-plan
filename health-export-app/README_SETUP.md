# HealthExporter App — 搭建步骤

这是一个只做一件事的 iPhone 小工具：读取你的 Apple Health 数据，每天把结果写成一个 JSON 文件推送进这个仓库的 `health-data/` 目录。

## 采集字段

- 训练记录（类型 / 时长 / 消耗 / 心率区间）
- 睡眠时长与阶段
- 静息心率
- HRV（心率变异性 SDNN）
- 步数
- 静息能量消耗（Resting/Basal Energy）
- 活动能量消耗（Active Energy）
- 活动圈数据（Move / Exercise / Stand）

体重不采集（不会自动更新），后续由训练计划直接询问你。

## 第一步：在 Xcode 里创建项目壳子

Xcode 项目文件（`.xcodeproj`）是二进制/易错格式，手写容易出问题，所以由你在 Xcode 里用向导创建最稳：

1. 打开 Xcode → File → New → Project
2. 选 **iOS → App**，Next
3. Product Name: `HealthExporter`
4. Interface: **SwiftUI**，Language: **Swift**
5. 存到你本地随便一个目录（不用存进这个仓库的 git 目录里也可以，等下我们把源码文件复制过去）
6. 创建好后，点项目名 → **Signing & Capabilities**：
   - Team 选你的 Apple ID（免费 Personal Team）
   - 点 `+ Capability`，加上 **HealthKit**
7. 点项目里的 `Info.plist`（或者在 Signing & Capabilities 下面的 Info 标签），添加两个 key（用途说明，苹果强制要求，没有的话 App 会直接崩溃）：
   - `Privacy - Health Share Usage Description` = "读取健康数据用于生成个性化训练计划"
   - （不需要 Health Update，因为我们只读不写）

## 第二步：替换源码文件

把 `health-export-app/HealthExporter/` 目录下的这几个 `.swift` 文件，拖进你 Xcode 项目里（替换掉向导自动生成的 `ContentView.swift` 和 App 入口文件）：

- `HealthExporterApp.swift` — App 入口
- `ContentView.swift` — 简单的设置界面（授权健康数据、填 GitHub Token、手动同步按钮）
- `HealthKitManager.swift` — 读取 Health 数据的核心逻辑
- `GitHubUploader.swift` — 把数据推送到这个仓库

## 第三步：准备 GitHub Token

去 GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens，创建一个：
- 只授权这一个仓库：`chloea27/personal-workout-plan`
- 权限只给 **Contents: Read and write**
- 生成后复制这个 token（只显示一次）

第一次打开 App 时会让你粘贴这个 token，它会存在 iPhone 的 Keychain 里（不会明文写进代码或仓库）。

## 第四步：跑起来

按之前说的步骤：接数据线 → Xcode 选中你的 iPhone → 点 ▶ → 手机上信任开发者证书 → 打开 App → 允许健康数据授权 → 点一下"立即同步"测试。

每 7 天签名过期后，重复"接数据线 → 点 ▶"即可，不用重新配置。

## 数据格式

每天会在仓库里生成一个文件，例如 `health-data/2026-07-23.json`：

```json
{
  "date": "2026-07-23",
  "steps": 8342,
  "restingHeartRate": 58.2,
  "hrvSDNN": 42.1,
  "restingEnergy": 1680.5,
  "activeEnergy": 512.3,
  "activitySummary": {
    "moveMinutes": 45,
    "exerciseMinutes": 32,
    "standHours": 10
  },
  "sleep": {
    "totalAsleepMinutes": 415,
    "inBedMinutes": 460,
    "stages": {
      "core": 220,
      "deep": 70,
      "rem": 95,
      "awake": 45
    }
  },
  "workouts": [
    {
      "type": "traditionalStrengthTraining",
      "start": "2026-07-23T18:00:00Z",
      "end": "2026-07-23T19:05:00Z",
      "durationMinutes": 65,
      "totalEnergyBurned": 380.0,
      "avgHeartRate": 128.4
    }
  ]
}
```

我读这个仓库的时候会直接解析这些文件来了解你的恢复状态和训练量，调整计划。
