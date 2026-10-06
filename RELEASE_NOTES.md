## OneStep Action 1.0.2

原生 macOS 菜单栏全局快捷键工具。

### 相对 1.0.1
- 新增：导出快捷键配置（保存面板，默认桌面，文件名含日期）
- 新增：导入快捷键配置（合并追加，自动跳过重复与按键冲突并提示统计）

### 功能
- 锁定屏幕
- 打开 App
- 打开 URL
- 执行 Shell 命令
- 导出 / 导入快捷键配置（JSON）

### 系统要求
- Apple Silicon（arm64）
- macOS 26.0+
- 首次使用需授予「辅助功能」权限

### 安装
1. 下载 `OneStep-Action-1.0.2.dmg`
2. 打开 dmg，将 **OneStep Action** 拖入「应用程序」
3. 首次打开：系统设置 → 隐私与安全性 → 辅助功能 → 勾选 OneStep Action

### 校验
```bash
lipo -info "/Applications/OneStep Action.app/Contents/MacOS/OneStep Action"
# Non-fat file: ... is architecture: arm64
```
