# Kumone iOS 15 构建说明

本工程的 iOS 最低部署目标为 **iOS 15.0**。公开仓库中的持续构建会在 macOS 环境依次解析 Swift Package 依赖、执行真机目标的 Release 编译、运行 iOS 模拟器 UI 测试，并生成 IPA 构件。每次工作流的运行名称均会显示触发构建的 GitHub 用户名，例如“由 `@用户名` 发起 · iOS 15 构建 #编号”，因此仓库页面可直接呈现本人发起的编译记录。

| 阶段 | 验证内容 | 产出 |
| --- | --- | --- |
| Release 编译 | `generic/platform=iOS`、`IPHONEOS_DEPLOYMENT_TARGET=15.0` | 设备目标 `.app` |
| UI 测试 | iPhone 模拟器中的导航、设置分组和下滑关闭路径 | 测试日志与 `.xcresult` |
| IPA 打包 | 将未经签名的 `.app` 按 iOS 标准 Payload 目录打包 | `Kumone-iOS15-unsigned.ipa` |

## 产物说明

工作流上传的 IPA 是 **未签名 IPA**。它可用于 TrollStore 或由侧载工具在本地签名后安装；若需直接分发到已注册设备或提交到 App Store，应当由仓库所有者配置有效的 Apple 开发者证书、描述文件与相应的签名流程。未配置这些私有凭据时，持续构建仍可完整验证源码能否生成 iOS 应用包。

## 本地复现

在安装 Xcode 的 macOS 设备上，从仓库根目录执行以下命令即可复现设备编译。命令显式禁用签名，适合先排查纯编译错误。

```bash
xcodebuild \
  -project ios/KumoneIOS.xcodeproj \
  -scheme KumoneIOS \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' \
  clean build
```

在 GitHub Actions 页面使用“Run workflow”手动触发后，可以在该次运行的 Artifacts 区域下载 IPA、设备编译日志、模拟器测试日志及测试结果包。
