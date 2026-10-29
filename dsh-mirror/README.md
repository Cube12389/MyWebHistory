# DSH 环境复刻脚本

把一台**全新安装的 DSH** 一次性变成与来源机器一致的状态。

## 用法

1. 先在目标机器上**启动一次 DSH**（让它生成 `%USERPROFILE%\.dsh\profiles\desktop`），然后完全退出。
2. 把整个 `.dsh-mirror` 文件夹拷到目标机器（U 盘/网盘都行）。
3. **双击 `setup.cmd`**，它会自动申请管理员权限并开始执行。
4. 看到 `[DONE]` 后，重新启动 DSH，刷新页面。

可重复执行，幂等；每次运行会先把现有配置备份到 `profiles\desktop\backup-<时间戳\`。

## 它会复刻什么

| 类别 | 内容 |
|---|---|
| 插件依赖 | dsh-m、dsh-pet、dsh-deepseek-web-free、dsh-concurrency-guard、@liustack/modsearch、dsh-endfield-theme、@leon___/dsh-client-liang-intensity-skin、dsh-startup-screen |
| bundles 顺序 | 与来源机器完全一致（含 `@deepseek-ai/dsh-experimental-agent-team-profile`） |
| 默认模型 | `deepseek-web` / `default`，reasoningEffort=on |
| 界面 | 深色主题、transcript 标准视图、详细性能面板、开发者工具 |
| agent 预设 | `default: standard`、`selectedDefault: cordis` |
| pnpm 配置 | `nodeLinker: hoisted`、`autoInstallPeers: false`、dsh-m 免最小发布期限制 |
| 特殊补丁 | `dsh-deepseek-web-free` 的 `nativeSearchActive()` 改为 `return false`，关掉网页版自带搜索（它会导致 DSH 误判服务不可用） |
| 启动动画 | `dsh-startup-screen` 从 `vendor-cache\` 离线复制到 profile 的 `vendor\`，以 link 依赖安装 |

## 目录结构

```
.dsh-mirror\
├─ setup.cmd                  入口（双击这个）
├─ setup-dsh-profile.ps1      实际逻辑
├─ setup-log.txt              运行日志（每次覆盖）
├─ README.md
└─ vendor-cache\
   └─ dsh-startup-screen\     dsh-startup-screen 源码离线缓存
```

## 可选参数

```powershell
# 指定别的 profile 目录
.\setup-dsh-profile.ps1 -ProfileDir 'D:\xxx\.dsh\profiles\desktop'

# 指定 DSH 自带的 node 运行时目录
.\setup-dsh-profile.ps1 -RuntimeDeps 'E:\deepseek\resources\runtime\primary-runtime\dependencies'

# 只改配置不装依赖 / 跳过 vendor 下载
.\setup-dsh-profile.ps1 -SkipInstall
.\setup-dsh-profile.ps1 -SkipVendorDownload
```

## 注意

- `dsh-deepseek-web-free` 的搜索补丁是**改 node_modules 产物**，该插件升级后会被覆盖，需要重跑本脚本。
- 脚本自动查找 DSH 自带的 node/pnpm（`%USERPROFILE%\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies` 或安装目录下的 `runtime\primary-runtime\dependencies`），目标机器**无需单独装 node/git**。
- 首次运行需要联网拉 npm 包；`dsh-startup-screen` 走本地缓存，不依赖 GitHub。
- 凭据（`.credentials.yaml`）**不会**被复制，目标机器需要自己登录一次。
