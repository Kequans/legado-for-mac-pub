#!/usr/bin/env swift

import AppKit
import Foundation

// 生成 App 图标
func generateAppIcon(size: CGSize, outputPath: String) {
    let image = NSImage(size: size)

    image.lockFocus()

    // 使用 macOS 图标规范的圆角矩形背景。
    let cornerRadius = size.width * 0.22
    let roundedRect = NSBezierPath(
        roundedRect: NSRect(origin: .zero, size: size),
        xRadius: cornerRadius,
        yRadius: cornerRadius
    )
    let gradient = NSGradient(colors: [
        NSColor(red: 0.25, green: 0.48, blue: 0.9, alpha: 1.0),
        NSColor(red: 0.1, green: 0.27, blue: 0.63, alpha: 1.0)
    ])
    NSGraphicsContext.current?.saveGraphicsState()
    roundedRect.addClip()
    gradient?.draw(in: NSRect(origin: .zero, size: size), angle: 135)
    NSGraphicsContext.current?.restoreGraphicsState()

    // 绘制书本图标
    let iconSize = size.width * 0.6
    let iconRect = NSRect(
        x: (size.width - iconSize) / 2,
        y: (size.height - iconSize) / 2,
        width: iconSize,
        height: iconSize
    )

    // 使用 SF Symbol
    if let bookImage = NSImage(systemSymbolName: "book.circle.fill", accessibilityDescription: nil) {
        bookImage.isTemplate = false

        // 设置白色
        let config = NSImage.SymbolConfiguration(pointSize: iconSize, weight: .regular)
        let tintedImage = bookImage.withSymbolConfiguration(config)

        NSColor.white.set()
        tintedImage?.draw(in: iconRect)
    }

    image.unlockFocus()

    // 保存为 PNG
    if let tiffData = image.tiffRepresentation,
       let bitmapImage = NSBitmapImageRep(data: tiffData),
       let pngData = bitmapImage.representation(using: .png, properties: [:]) {
        try? pngData.write(to: URL(fileURLWithPath: outputPath))
        print("✅ 生成图标: \(outputPath)")
    }
}

// 生成不同尺寸的图标
let sizes: [(size: Int, scale: Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2)
]

let basePath = "Resources/Assets.xcassets/AppIcon.appiconset"

for (size, scale) in sizes {
    let actualSize = CGFloat(size * scale)
    let filename = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@\(scale)x.png"
    let outputPath = "\(basePath)/\(filename)"
    generateAppIcon(size: CGSize(width: actualSize, height: actualSize), outputPath: outputPath)
}

print("✅ 所有图标生成完成")
