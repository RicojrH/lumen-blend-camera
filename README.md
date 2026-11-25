# 自动溶图相机 · LumenBlend Camera (Flutter iOS / Android)

- **作者**：@没品人类之一
- **B站主页**：https://space.bilibili.com/396896138

一款跨平台 **iOS / Android** 二次元立绘实景融合相机应用：结合**实时 3D 透视网格预览**、**GPU 物理光影着色器实时匹配**、**端侧高清无损合成与可选 AI 深度重绘**，以及**内置混合自动抠图工作台**，将二次元立绘以光影一致、接地自然的方式无缝融入现实照片中。

---

## 核心功能模块

### 1. 实时取景溶图相机（默认主界面 · `CameraBlendScreen`）
- **真机相机 + 模拟实景双模式**：iOS/Android 真机默认开启高画质后置/前置摄像头并实时采样画面光影；在桌面端或室内无真机环境下，自动支持**模拟实景测试模式**（内置「午后暖阳咖啡馆」「雨夜东京霓虹巷」「樱花林荫步道」三套不同色温与光照方向的实景样片，也支持从相册导入任意实景背景图）。
- **实时 3D 透视与放置定位**：融合手机加速度/重力传感器实时计算相机俯仰角（Pitch）、滚转角（Roll）、地平线高度与消失点，绘制 3D 地面透视网格与脚底锚点环；拖动角色在地面前后移动时按透视深度自动近大远小，支持双指缩放、旋转、镜像翻转与一键复位。
- **60fps GPU 物理光影预览 (`shaders/harmonize.frag`)**：实时采样场景色温（Kelvin）、曝光（EV）、主光源方向（Azimuth）、地面环境反光色与暗部黑电平，在取景器内即时呈现色温匹配、轮廓受光（Rim Light）、脚底接触阴影（Contact AO）、方向投影与光学边缘溢光（Light Wrap）。

### 2. 图库查看与无损「再次溶图」（`GalleryScreen` & `PhotoEditorScreen`）
- **非破坏性工程配方存储**：每次拍摄不仅保存高清成品，还会保留原始环境照片与完整的 `BlendRecipe`（立绘引用、站位、透视参数、完整光影参数）。
- **实时效果微调**：在图库点开任意成品即可通过 GPU 实时重调色温、曝光、对比度、饱和度、暗部空气感抬升、主光罗盘方向、阴影浓度/羽化、光源仰角（影长）、景深虚化（DOF）与 CMOS 噪点。
- **再次溶图**：支持在原实景中直接更换其他二次元立绘、重新拖拽站位与透视，或一键「带入相机再次溶图」；支持左右滑动**对比窗帘**（原图 / 端侧物理溶图 / AI 深度精修）。
- **可选 AI 深度光影重绘 (`AiRelightingService`)**：在右上角「设置」中填入 API Key 或服务地址后，可一键调用 **Google Gemini 图像重绘**、**OpenAI GPT-Image 编辑** 或自建 **IC-Light / ComfyUI 接口**（自动将当前探测到的色温/光源方向写入物理光影约束 Prompt）。

### 3. 素材库与智能自动抠图工作台（`AssetLibraryScreen` & `MatteStudioScreen`）
- **开箱即用的内置示例立绘**：首次启动自动对内置二次元立绘执行自动抠图，立即体验溶图全流程，也支持随时点开「抠图精修」测试抠图能力。
- **自由导入 JPG / PNG / WebP 并自动去背景**：
  - **二次元护线抠图（默认推荐）**：边缘连通域 + CIE Redmean 感知色距 + 线稿梯度屏障，精准去除纯白/浅色/渐变背景的同时，完整保护角色内部的白色衣领、白袜与眼神高光，并内置**去白边溢色净化（Color Decontamination / Defringe）**与边缘羽化/收缩。
  - **边缘智能抠 / 吸色去背（绿幕/蓝幕）**：适配纯色渐变背景与需全局抠除镂空区域的场景。
  - **端侧 ONNX AI 语义抠图（可选）**：基于 `flutter_onnxruntime`，可在设置中加载本地 `.onnx` 模型（兼容 **RMBG-1.4** / **IS-Net-Anime** / **U²-Net**）离线处理复杂背景插画。
  - **手动精修工具箱**：支持「缩放查看」「擦除背景画笔」「恢复主体画笔」「魔棒去孔洞」「吸管取色」与撤销操作，支持在棋盘格 / 黑底 / 白底 / 实景下实时检查抠图边缘。

---

## 快速运行指南（iOS / Android / 本地浏览器直看）

> **本机已配置工具链**：已在 `E:\flutter_toolchain` 自动安装便携版 MinGit 与 **Flutter 3.50.1 (Dart 3.14)** 并写入当前用户环境变量（同时已配置官方国内镜像 `pub.flutter-io.cn` / `storage.flutter-io.cn`）。

### 1. 直接在浏览器启动实时交互版
```powershell
flutter run -d chrome
```
或直接编译离线静态包并启动本地服务：
```powershell
flutter build web --release --no-web-resources-cdn
```

### 2. 打包 iOS 真机 `.ipa`（支持无 Mac 电脑云端打包）
> 由于苹果官方限制，编译 `.ipa` 必须使用 macOS 上的 **Xcode** 工具链（Windows 无法直接本地编译 `.ipa`）。项目已完整配置好 iOS 15+ `Podfile`、Flutter 3.50 `SceneDelegate`、`Info.plist` 相机/相册/陀螺仪权限及包名 `com.meipinrenlei.lumenblend`，提供两种打包方式：

- **方式 A（推荐，无需 Mac）：GitHub Actions 免费 macOS 云端自动打包**
  1. 将本项目推送至任意 GitHub 仓库（公开或私有均可）。
  2. 打开仓库的 **Actions → Build iOS IPA (LumenBlend)**，自动触发（或点击 **Run workflow**）。
  3. 约 5 分钟后在产物（Artifacts）中直接下载 **`LumenBlend-iOS-IPA`**（内含 `LumenBlend_iOS_unsigned.ipa`）。
  4. 在 Windows 上使用 **Sideloadly** / **爱思助手（Apple ID 签名）** / **AltStore** 将该 `.ipa` 安装到 iPhone 真机测试即可。
- **方式 B（若有 Mac + Xcode）**：
  ```bash
  bash scripts/build_ipa_macos.sh
  ```
  或签名导出：`flutter build ipa`

### 3. Android 真机构建（待 iOS 验证通过后按需执行）
```bash
flutter build apk --release
```

### 3. Android / iOS 真机构建注意事项
- **Android (`android/app/build.gradle`)**：确保 `minSdk` 设为 `24` 或更高（`camera` CameraX 与 `flutter_onnxruntime` 要求 Android API 24+）。
- **iOS (`ios/Podfile`)**：确保最低部署版本为 `platform :ios, '13.0'`，执行 `cd ios && pod install` 后用 Xcode 签名真机运行。
- **桌面端快速测试**：执行 `flutter run -d windows` 或 `flutter run -d macos`，应用会自动进入「模拟实景测试模式」，无需手机即可完整体验透视网格、GPU 实时溶图、抠图工作台与图库二创。

---

## 目录结构

```text
├── pubspec.yaml                       # 依赖、着色器与内置素材声明
├── shaders/
│   └── harmonize.frag                 # 60fps GPU 物理光影融合 GLSL 片元着色器
├── assets/samples/
│   ├── standees/                      # 内置二次元立绘示例 (JPG，首启自动抠图)
│   └── scenes/                        # 内置三套多光影实景测试背景
├── lib/
│   ├── main.dart                      # 应用入口与首启加载页
│   ├── theme/app_theme.dart           # 专业暗色相机 UI 主题
│   ├── models/                        # 立绘素材、非破坏溶图配方、图库项、设置模型
│   ├── services/
│   │   ├── perspective_engine.dart    # 传感器融合与 3D 透视平面数学
│   │   ├── lighting_probe_service.dart# 实时相机帧 & 静图环境光影探测引擎
│   │   ├── compositor_engine.dart     # 高清离屏 Isolate 物理合成与双层阴影引擎
│   │   ├── auto_matte_engine.dart     # 混合自动抠图（二次元护线/吸色/ONNX AI/画笔）
│   │   ├── ai_relighting_service.dart # Gemini / OpenAI / IC-Light AI 深度重绘接口
│   │   └── storage_service.dart       # 本地持久化、首启种子抠图与系统相册导出
│   ├── state/app_controller.dart      # 全局响应式状态管理
│   ├── widgets/                       # 透视网格、GPU 立绘视图、光影 HUD/罗盘、对比滑块
│   └── screens/                       # 相机取景 / 图库 / 无损编辑重溶 / 素材库 / 抠图工作台 / 设置
├── android/app/src/main/AndroidManifest.xml
├── ios/Runner/Info.plist
└── test/                              # 透视、光影探测、自动抠图、配方序列化单元测试
```
