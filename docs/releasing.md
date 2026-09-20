# Duo Status 发布说明

## 当前阶段

当前版本以 Apple silicon 的无签名 macOS zip 包为发布产物，版本号为 `1.1.0`、build `2`。签名、公证和 helper 的正式授权暂不纳入本阶段；无签名包适合个人测试或手动分发，不应宣称为免警告的正式安装包。

## 发布前检查

1. 在 Apple silicon Mac 上完成电池、Wi-Fi 只读状态、系统 Wi-Fi 设置入口、辅助进程降级和能源模式的手动验收。
2. 运行单元测试和完整测试：

   ```sh
   xcodebuild -project mac-duo-status.xcodeproj -scheme mac-duo-status -destination 'platform=macOS' test
   ```

3. 生成无签名发布包：

   ```sh
   ./scripts/package-unsigned-release.sh
   ```

4. 在干净用户环境中确认：应用可以启动、菜单栏入口可用、不会出现额外的 Wi-Fi/定位授权提示、网络卡可以打开系统 Wi-Fi 设置，且未授权 helper 时不会显示伪造的写入成功状态。
5. 将 zip 和对应的 `.sha256` 文件一起发布，并在发布说明中明确 Apple silicon、macOS 13+ 和无签名限制。

## 产物

脚本会生成：

- `build/release/DuoStatus-v1.1.0-macos-arm64-unsigned.zip`
- `build/release/DuoStatus-v1.1.0-macos-arm64-unsigned.zip.sha256`

包内包含主应用、helper 可执行文件和 LaunchDaemon plist。由于本阶段不签名，helper 不应被当作已授权能力；应用必须继续提供只读回退。

## 版本与 GitHub Release

现有 `v1.0.0` Release 对应旧提交。发布当前代码时应先提交版本变更，再创建新的 `v1.1.0` tag 和 GitHub Release，不要复用旧 tag。

## 暂不执行的签名流程

后续具备 Apple Developer 发行条件后，再补充 Developer ID Application 签名、notarization、staple 和已签名 helper 的实机授权验收。签名之前不要把无签名包描述为经过 Apple 公证。
