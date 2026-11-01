# 翻译工具快速入门

最新命令说明见 [tools/README.md](../README.md)。翻译术语和审核规则以
[TERMINOLOGY.md](../../TERMINOLOGY.md) 为准。本页仅提供快速入门示例。

在仓库根目录运行：

```sh
# 只读：检查源码与翻译目录的覆盖情况
bash dots/.config/quickshell/ii/translations/tools/manage-translations.sh status

# 只读：检查占位符、标记、命令等结构
bash dots/.config/quickshell/ii/translations/tools/manage-translations.sh check --json

# 预览向现有语言目录补充缺失键的计划
bash dots/.config/quickshell/ii/translations/tools/manage-translations.sh sync -l zh_CN

# 确认计划后，显式补充缺失键
bash dots/.config/quickshell/ii/translations/tools/manage-translations.sh sync -l zh_CN --apply
```

默认路径相对于脚本自身解析，不依赖当前工作目录。只有 `sync --apply`
（或 `update --apply`）会写入文件。工具保留现有译文和额外的键，并为每个
有改动的文件保存原始内容备份。补入的英文内容仍需翻译。

`clean` 仅生成覆盖情况报告，绝不会删除键。静态扫描可能漏掉动态调用，
不能据此认定某个键已无用途。请勿复用已移除的一次性语言构建脚本或已否决的
翻译草稿，也不要将简体中文转换为繁体中文来代替直接从英文翻译。
