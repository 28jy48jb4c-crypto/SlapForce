# SlapForce

SlapForce 是一个 macOS 菜单栏 SwiftUI 应用，运行在 Apple Silicon MacBook 上，通过内置加速度传感器识别拍打/碰撞，再按模式、力度和声音素材层级播放动态音效。

目前项目已经具备：

- Apple Silicon 内置加速度传感器读取
- 拍打峰值检测与去重，尽量避免一拍双响
- 四种声音模式：`性感 / 经典 / 动物 / 惊喜`
- 单素材自动派生 `轻 / 中 / 重` 三档
- 多素材强弱分析与匹配
- `性感` 模式的状态化升温机制

## 项目目录

代码仓库目录：

```text
/Users/84471753qq.com/Documents/Codex/mac 声音拍打管理器/SlapForce
```

主要结构：

- `SlapForce/App`：应用入口、窗口和菜单栏行为
- `SlapForce/Services/HIDAccelerometerService.swift`：AppleSPUHIDDevice 读取与 Bosch IMU 数据解码
- `SlapForce/Services/SlapMonitor.swift`：拍打检测、峰值锁定、去重和触发逻辑
- `SlapForce/Services/SoundModeManager.swift`：四模式素材扫描、派生池、声音选择和动态播放
- `SlapForce/Views/ContentView.swift`：主界面与调试信息
- `Assets/SoundsSeed`：仓库内声音素材备份
- `Assets/ThemesSeed`：预留的主题备份目录
- `Assets/ModeLibrarySeed`：预留的模式库备份目录

## 运行时资源目录

SlapForce 运行时默认从下面这些目录读取资源：

```text
~/Library/Application Support/SlapForce/Sounds
~/Library/Application Support/SlapForce/Themes
~/Library/Application Support/SlapForce/ModeLibrary
```

其中最重要的是：

```text
~/Library/Application Support/SlapForce/Sounds
```

这是应用运行时真正扫描的声音目录。

## 双保险保存策略

为了后面继续开发、换机器恢复、上传 GitHub 时不丢素材，项目采用双保险：

1. 运行时目录保留一份  
   程序直接从 `~/Library/Application Support/SlapForce/Sounds` 读取声音。

2. 仓库内再保留一份  
   所有确认值得留存的素材，同步备份到：

```text
Assets/SoundsSeed
```

以后新增素材时，建议固定做法：

1. 先把音频放到 `~/Library/Application Support/SlapForce/Sounds`
2. 测试可用后，再复制一份到 `Assets/SoundsSeed`
3. 在应用里点击 `重新扫描`

## 后续继续开发时怎么恢复

如果以后停一段时间，再回来继续做，按这个流程即可：

1. 打开 Xcode 工程：

```text
SlapForce/SlapForce.xcodeproj
```

2. 检查运行时声音目录是否存在：

```text
~/Library/Application Support/SlapForce/Sounds
```

3. 如果运行目录缺失，就把仓库内备份复制回去：

```text
Assets/SoundsSeed -> ~/Library/Application Support/SlapForce/Sounds
```

4. 启动 App，点击 `重新扫描`

5. 继续测试和开发

也可以直接用脚本：

```bash
./scripts/restore_runtime_sounds.sh
```

如果你想开一个新的 Codex 线程继续开发，可以先看：

```text
docs/CONTINUE_WITH_CODEX.md
```

也可以直接打印一份当前恢复信息和建议提示词：

```bash
./scripts/print_resume_context.sh
```

## 同步最新素材回仓库

当你在运行目录里新增或筛选过素材，想把它们同步回仓库备份时，可以运行：

```bash
./scripts/sync_runtime_sounds_to_seed.sh
```

这个脚本会用当前运行目录内容覆盖仓库内 `Assets/SoundsSeed`。

## 素材命名建议

### 四种模式基础关键字

文件名里包含这些关键字时，会自动归类：

- `性感` / `sexy`
- `经典` / `classic`
- `动物` / `animal`
- `惊喜` / `surprise`

### 性感模式分层建议

`性感` 模式支持按文件名识别更细的素材层级。推荐命名：

```text
性感-soft-01
性感-warm-01
性感-hot-01
```

或者中文：

```text
性感-轻柔-01
性感-贴近-01
性感-炽热-01
```

当前识别倾向大致是：

- `soft / gentle / light / calm / 温柔 / 轻 / 柔` -> 轻柔层
- `warm / tease / close / 暖 / 贴近 / 投入` -> 贴近层
- `hot / intense / moan / breath / 热 / 炽热 / 浓` -> 炽热层

如果文件名没有这些词，系统也会退回用音频强弱自动分析。

## 开发检查清单

每次回来继续开发，建议先看这几项：

1. `音效库状态` 是否识别到了原始音频
2. `当前档位` 是否会按拍打力度变化
3. `触发锁定` 和 `已忽略次峰` 是否正常，确认没有重复触发
4. `性感状态` 和 `素材层级` 是否与听感一致

## Git 说明

这个项目应该使用 **SlapForce 项目目录自己的独立 Git 仓库**，不要使用错误挂在家目录上的上级仓库。  
后续提交、打分支、推 GitHub，都在这个目录里做：

```text
/Users/84471753qq.com/Documents/Codex/mac 声音拍打管理器/SlapForce
```
