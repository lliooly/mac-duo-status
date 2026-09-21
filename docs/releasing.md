# Duo Status 发布说明

## v2.0.0 发布范围

`v2.0.0` 是 Apple silicon 优先的 macOS 13+ 版本，发布形式为没有 Developer ID 签名的 DMG 和 ZIP。当前不购买 Developer ID，也不执行 notarization；Gatekeeper 首次打开提示属于预期行为。

本版本包含菜单栏状态入口、SwiftUI 弹出面板、设置面板、Widget 扩展、状态共享快照和能源模式安全降级。能源模式 helper 的正式签名、安装和授权不在本次发布门禁内，helper 不可用时应用保持只读。

## 发布前检查

1. 停止旧的应用、Widget 和构建进程，清理旧的 `build/`、DerivedData 和 `dist/` 产物。
2. 在 Apple silicon Mac 上验证菜单栏入口、弹出面板、设置、网络系统设置入口和只读降级。
3. 运行单元测试：

   ```sh
   xcodebuild \
     -project mac-duo-status.xcodeproj \
     -scheme mac-duo-status \
     -destination 'platform=macOS' \
     test
   ```

4. 生成无签名发布包：

   ```sh
   ./scripts/package-unsigned-release.sh
   ```

5. 检查 `dist/` 中的 DMG、ZIP 和 SHA-256 文件，并在隔离目录中打开 DMG 验证应用包结构。
6. 在发布说明中明确 Apple silicon、macOS 13+、无签名和 Gatekeeper 手动放行要求。

## 产物

脚本会生成：

- `dist/DuoStatus-v2.0.0-macos-arm64-unsigned.dmg`
- `dist/DuoStatus-v2.0.0-macos-arm64-unsigned.zip`
- 两个产物对应的 `.sha256` 校验文件

应用包内包含 Widget 扩展和能源模式 helper 文件。由于本阶段不签名，helper 不应被当作已授权能力；目标系统如果拒绝无签名 App Group 容器，建议从 Xcode 以自己的 Team 构建并运行。

## Gatekeeper 使用说明

没有 Developer ID 的 DMG 不会获得 Apple 公证票据。用户下载后应在 Finder 中对应用右键选择“打开”；如果仍被拦截，可在“系统设置 → 隐私与安全性”中点击“仍要打开”。确认来源可信后，也可以使用：

```sh
xattr -dr com.apple.quarantine /Applications/mac-duo-status.app
```

这只是本地手动放行，不等于 Developer ID 签名或 notarization。

## 版本与 GitHub Release

发布提交完成后创建 `v2.0.0` tag，并将 DMG、ZIP 和校验文件上传到 GitHub Release。不要复用已有的 `v1.0.0` 或 `v1.1.0` tag。

后续如果具备 Apple Developer 发行条件，再补充 Developer ID Application 签名、Hardened Runtime、notarization、staple 和已签名 helper 的实机验收。
