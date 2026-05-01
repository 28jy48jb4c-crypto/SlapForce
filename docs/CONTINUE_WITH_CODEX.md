# Continue SlapForce With Codex

这个文件是给“未来的新线程”准备的。

如果你明天、下周、或者换一台机器之后，想继续和 Codex 一起开发 SlapForce，最简单的做法是直接把下面这段话发给新的 Codex 线程。

## 推荐开场模板

### 通用继续开发

```text
继续开发 SlapForce。
项目在 /Users/84471753qq.com/Documents/Codex/mac 声音拍打管理器/SlapForce
先读 README.md。
如果需要声音素材，先检查：
~/Library/Application Support/SlapForce/Sounds
和
Assets/SoundsSeed
是否一致。
然后再继续实现或优化。
```

### 新增素材之后继续

```text
继续开发 SlapForce。
项目在 /Users/84471753qq.com/Documents/Codex/mac 声音拍打管理器/SlapForce
先读 README.md。
我刚往 ~/Library/Application Support/SlapForce/Sounds 放了几条新素材，
请先检查重新扫描逻辑和当前模式命中情况，
再帮我优化听感。
```

### 重点做性感模式

```text
继续开发 SlapForce。
项目在 /Users/84471753qq.com/Documents/Codex/mac 声音拍打管理器/SlapForce
先读 README.md。
重点看性感模式。
请先检查 Assets/SoundsSeed 和运行时 Sounds 目录中的素材，
然后帮我优化素材层级命中、状态升温和听感差异。
```

### 重点做动物模式

```text
继续开发 SlapForce。
项目在 /Users/84471753qq.com/Documents/Codex/mac 声音拍打管理器/SlapForce
先读 README.md。
重点看动物模式。
我新增了几条狗叫素材，请先检查轻/中/重档位命中，
以及是否还有一拍双响或素材随机不合理的问题。
```

## 开新线程前你自己先做什么

如果你刚收集完新声音素材，建议先做这几步：

1. 把素材放进：

```text
~/Library/Application Support/SlapForce/Sounds
```

2. 命名尽量带模式和层级，例如：

```text
性感-soft-01
性感-warm-01
性感-hot-01
动物-狗叫14
```

3. 如果素材验证后值得保留，再执行：

```bash
./scripts/sync_runtime_sounds_to_seed.sh
```

这样新线程打开时，Codex 能同时看到：

- 运行时最新素材
- 仓库内备份素材
- 当前项目说明

## 如果换机器

先恢复素材，再开新线程：

```bash
./scripts/restore_runtime_sounds.sh
```

然后再按上面的模板告诉 Codex 从 `README.md` 开始读。
