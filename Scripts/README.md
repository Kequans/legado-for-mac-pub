# 辅助脚本

- generate_icon.swift：使用 macOS AppKit 生成图标 PNG 资源。

应用包构建入口位于根目录 build_app.sh。它会直接使用 Resources/Assets.xcassets/AppIcon.appiconset 中的资源生成 icns；只有修改图标源逻辑时才需要单独运行本目录的脚本。
