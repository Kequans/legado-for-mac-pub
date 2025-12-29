# Legado macOS App 构建指南

## 快速开始

### 方式一：使用预构建的 App（推荐）

如果已经有 `Legado.app`，直接双击运行即可。

**首次运行注意事项：**
1. 双击 `Legado.app`
2. 如果提示"无法打开"，请前往「系统偏好设置 > 隐私与安全性」
3. 点击"仍要打开"按钮
4. 再次双击 `Legado.app` 即可运行

### 方式二：从源码构建

```bash
# 1. 生成应用图标
swift generate_icon.swift

# 2. 构建 App
./build_app.sh

# 3. 运行 App
open Legado.app
```

## App 结构

```
Legado.app/
├── Contents/
│   ├── Info.plist          # App 配置信息
│   ├── MacOS/
│   │   └── Legado          # 可执行文件
│   └── Resources/
│       └── AppIcon.icns    # 应用图标
```

## 安全保护措施

本 App 包含以下基本保护措施：

1. **代码签名** - 使用 ad-hoc 签名（本地签名）
2. **Info.plist 配置** - 限制文件访问权限
3. **Release 编译** - 优化代码，移除调试信息
4. **图标资源** - 使用自定义图标，提升专业度

### 关于代码签名

当前使用的是 ad-hoc 签名（`codesign --sign -`），这是一种本地签名方式：
- ✅ 可以在本机正常运行
- ✅ 提供基本的代码完整性保护
- ⚠️ 无法通过 App Store 分发
- ⚠️ 其他用户首次运行需要在系统设置中允许

**如需更强的保护：**
1. 申请 Apple Developer 账号
2. 获取开发者证书
3. 使用真实证书签名：`codesign --sign "Developer ID Application: Your Name" Legado.app`
4. 可选：进行公证（Notarization）

## 分发 App

### 方式一：直接分发（当前方式）

```bash
# 打包为 zip
zip -r Legado.zip Legado.app

# 或创建 DMG
hdiutil create -volname "Legado" -srcfolder Legado.app -ov -format UDZO Legado.dmg
```

**用户安装步骤：**
1. 下载 `Legado.app` 或 `Legado.dmg`
2. 拖拽到「应用程序」文件夹
3. 首次运行时在「系统偏好设置 > 隐私与安全性」中允许

### 方式二：开发者签名分发（推荐）

需要 Apple Developer 账号（$99/年）：

```bash
# 1. 使用开发者证书签名
codesign --deep --force --verify --verbose --sign "Developer ID Application: Your Name" Legado.app

# 2. 公证（可选但推荐）
xcrun notarytool submit Legado.zip --apple-id your@email.com --team-id TEAMID --password app-specific-password

# 3. 装订公证票据
xcrun stapler staple Legado.app
```

## 常见问题

### Q: 为什么首次运行需要在系统设置中允许？

A: 因为使用的是 ad-hoc 签名，macOS 的 Gatekeeper 会阻止未经公证的 App。这是正常的安全机制。

### Q: 如何避免每次都需要允许？

A: 有两种方式：
1. 在「系统偏好设置 > 隐私与安全性」中允许后，后续运行不再需要
2. 使用开发者证书签名并进行公证

### Q: App 可以在其他 Mac 上运行吗？

A: 可以，但其他用户首次运行时也需要在系统设置中允许。

### Q: 如何更新 App 图标？

A: 修改 `generate_icon.swift` 脚本，然后重新运行构建流程。

## 技术细节

### 编译优化

Release 编译会自动进行以下优化：
- 代码优化（-O）
- 移除调试符号
- 减小二进制文件大小
- 提升运行性能

### 图标生成

使用 SF Symbols 的 `book.circle.fill` 图标：
- 蓝色渐变背景
- 白色书本图标
- 支持所有 macOS 所需尺寸（16x16 到 1024x1024）

### 文件关联

App 已配置支持以下文件类型：
- `.txt` - 纯文本文件
- `.epub` - EPUB 电子书

## 进阶：增强保护措施

如果需要更强的保护，可以考虑：

1. **代码混淆** - 使用 Swift 混淆工具
2. **加密资源** - 加密敏感资源文件
3. **运行时检查** - 检测调试器、越狱等
4. **网络验证** - 在线验证授权

但请注意：
- 这些措施会增加复杂度
- 可能影响用户体验
- 对于开源项目意义不大

## 许可证

GPL-3.0 License
