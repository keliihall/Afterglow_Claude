# Claude 余量 · macOS 桌面挂件

极简、半透明、可拖动的原生 macOS 桌面常驻挂件，实时显示 **Claude 订阅的真实余量**——
和 Claude 桌面应用里「Plan usage」面板完全一致的数据：滚动 **5 小时**窗口与**每周**窗口的剩余百分比和重置时间。
原生 SwiftUI 编写，体积小、与系统观感一致（毛玻璃材质），默认停靠在桌面右下角。

## 显示什么（全部为官方真实数据）

| 区域 | 含义 |
|------|------|
| `5h  82%余` | 滚动 5 小时窗口的剩余额度 + 进度条 + `重置 13:11` |
| `1w  88%余` | 每周（所有模型）的剩余额度 + 进度条 + `重置 6/30` |
| 模型行（如 `Sonnet`） | 某模型的单独周限额——仅在该限额开始被占用时才显示 |
| `MAX` 徽标 | 你的订阅等级（max / pro …） |
| 右上角圆点 | 绿=正常 / 黄=数据偏旧 / 红=读取失败 |

进度条颜色随余量变化：绿（充足）→ 黄（偏低）→ 红（紧张）。鼠标悬停看「已用/剩余/重置」明细。

数据与 Claude 官方完全一致，因为它读取的就是 Claude 自己用的接口
`GET https://api.anthropic.com/api/oauth/usage`。

## 工作原理

1. 读取 Claude 桌面应用的配置 `~/Library/Application Support/Claude/config.json` 里的
   `oauth:tokenCacheV2`（OAuth 访问令牌，由 Electron `safeStorage` 加密）。
2. 用 macOS 钥匙串里的 **`Claude Safe Storage`** 密钥解密令牌
   （AES-128-CBC，PBKDF2-SHA1/`saltysalt`/1003 轮，与 Chromium safeStorage 同方案）。
3. 用该令牌（`Authorization: Bearer …` + `anthropic-beta: oauth-2025-04-20`）调用
   `/api/oauth/usage`，解析其中的 `limits` 数组（`session` = 5h，`weekly_all` = 1w，`weekly_scoped` = 单模型）。
4. 默认每 60 秒刷新。令牌由 Claude 桌面应用自动续期，挂件每次刷新都重新读取最新令牌。

> **首次启动会弹一次钥匙串授权框**（因为要读取 `Claude Safe Storage` 密钥）。
> 点 **「始终允许 / Always Allow」**，以后就不再询问。
>
> **前提**：本机装有并登录了 Claude 桌面应用（它负责保持令牌有效）。
> 若令牌过期且 Claude 未运行，挂件会提示「登录过期，请打开 Claude」。

## 构建

仅需 Xcode Command Line Tools（无需完整 Xcode）：

```bash
./setup-signing.sh   # 仅需运行一次：创建固定的本地签名身份
./build.sh
open "build/Claude 用量.app"
```

`setup-signing.sh` 会在一个专用的本地钥匙串里生成一个**固定的自签名代码签名证书**，
让 App 每次重新编译后**签名保持不变**。这样你在钥匙串授权框点一次「始终允许」后，
即使以后重新编译，也**不会再次弹窗**（钥匙串授权是按签名记忆的）。
不运行它也能编译（会退回临时 ad-hoc 签名），只是每次重新编译后会再弹一次授权框。

安装到应用程序文件夹（推荐，签名稳定后钥匙串只需授权一次）：

```bash
cp -R "build/Claude 用量.app" /Applications/
open "/Applications/Claude 用量.app"
```

## 操作

- **拖动**：在挂件任意位置按住拖动即可移动，位置自动记忆；窗口移出屏幕时会自动归位。
- **菜单**：点击菜单栏的仪表盘图标，或在挂件上右键，可设置：
  - 立即刷新
  - 置顶显示（开/关）
  - 毛玻璃背景（开/关，关闭则为纯深色半透明）
  - 不透明度（50% / 65% / 80% / 92% / 100%）
  - 开机自启动
  - 重置到右下角
  - 退出

## 文件结构

```
Sources/
  main.swift            程序入口
  AppController.swift    窗口 / 菜单栏 / 拖动 / 置顶 / 开机自启 / 离屏归位
  ContentView.swift      SwiftUI 界面（极简深色半透明，余量进度条）
  UsageModel.swift       数据层：解密 OAuth 令牌 + 调 /api/oauth/usage + 解析 limits
  VisualEffectView.swift 毛玻璃材质
  AppSettings.swift      偏好（不透明度 / 置顶 / 毛玻璃 / 刷新频率）
build.sh                 用 swiftc 编译并打包成 .app
```

## 隐私

挂件只在你本机读取你自己的 Claude 令牌，且仅把它发给 **你自己的** Anthropic 账号用量接口
（与 Claude 桌面应用、Claude Code CLI 完全一致的接口）。不向任何第三方上传数据。

## 备注

- 这是基于 Claude 桌面应用当前（v1.15962 / 内置 CLI 2.1.187）的令牌存储方式实现的。
  若官方将来改了存储格式或接口，解密/取数逻辑需相应更新。
- `utilization` 是「已用百分比」，挂件显示的「余量」= 100 − 已用。
