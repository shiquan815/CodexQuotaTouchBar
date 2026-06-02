# Codex Quota Touch Bar

一个用于 macOS 菜单栏和 Touch Bar 的个人小工具，用来显示本机 Codex 的 5 小时额度和每周额度状态。

它优先通过本机 Codex app-server 读取额度信息；如果读取失败，会回退读取本地 Codex 会话 JSONL 文件中的最近一次额度数据。

## 功能

- 在菜单栏显示 Codex 5 小时额度和每周额度剩余百分比。
- 在 Touch Bar 的 Control Strip / system tray 中注册一个小图标按钮。
- 点击 Touch Bar 图标后，展开两行紧凑额度面板。
- 本地计算并显示额度重置倒计时。
- 支持可选自定义图标素材，并自动叠加红到绿的额度风格外圈。

## 数据来源

应用会按顺序尝试读取：

1. 本机 Codex app-server：
   ```sh
   codex app-server --listen stdio://
   ```
2. 本机最新 Codex 会话 JSONL：
   ```text
   ~/.codex/sessions
   ```

应用会自动查找 Codex 可执行文件：

1. `/Applications/Codex.app/Contents/Resources/codex`
2. `~/.vscode/extensions/openai.chatgpt-*/bin/macos-x86_64/codex`
3. `which codex`

## 界面

菜单栏示例：

```text
5h 93% W 96%
```

Touch Bar 展开面板示例：

```text
[x] [图标]  5h    ||||||||||||||||||||  93%   4h 12min
            week  |||||||||||||||||||||  96%   3天
```

如果每周额度距离重置不足一天，会显示为小时和分钟。

## 构建

依赖：

- 带 Touch Bar 的 macOS 设备
- Xcode Command Line Tools
- `clang`
- `node`
- `sips`

构建：

```sh
./build.sh
```

生成的应用位于：

```text
build/CodexQuotaTouchBar.app
```

你可以把它复制到：

```text
/Applications/CodexQuotaTouchBar.app
```

## 可选图标素材

仓库默认不包含任何 Codex/OpenAI 官方图标素材。

如果你想使用自己的本地图标图片，可以放到：

```text
Assets/codex.webp
```

构建脚本会把这张图放入红到绿的渐变外圈中。如果没有这个文件，应用会自动使用一个简单生成的 `C` 标记作为图标。

`Assets/codex.webp` 已被 `.gitignore` 忽略。

## 隐私说明

这个应用不会发送模型提示词，也不会消耗 Codex 模型额度。

它只读取本机 Codex app-server 返回的账户/额度元数据；在 app-server 不可用时，可能会读取本机 Codex 会话 JSONL 文件中的额度字段作为兜底。应用不会上传这些文件。

## 重要限制

本项目使用了 macOS Touch Bar 私有 API，包括 system tray 和 system modal Touch Bar 相关 selector。这些 API 不是 Apple 公开文档的一部分，macOS 更新后可能失效。

这个应用适合个人使用，不适合上架 App Store。

## 商标声明

本项目与 OpenAI 无关联。Codex、OpenAI、ChatGPT、macOS 和 Touch Bar 是其各自所有者的商标。

请不要在没有授权的情况下重新分发第三方品牌图标素材。
