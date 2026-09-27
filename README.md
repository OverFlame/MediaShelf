# MediaShelf

本地音频播放器（Windows / Linux / Android），以「作品集（专辑）＋虚拟文件夹」方式管理本地音频，支持字幕模式、自定义封面与标签筛选。

> **现状**：代码是 AudioShelf 骨架原样迁入，下面这份功能清单与实际一致。合并 PictureViewer2 的图片与视频栈的施工方案见 [BUILD_GUIDE.md](BUILD_GUIDE.md)，分阶段施工记录见 [PROJECTLOG.md](PROJECTLOG.md)。

## 功能

- **添加文件夹**：导入指定文件夹的全部音频（mp3 / wav），递归扫描。
- **作品集（专辑）**：主页以文件夹作品卡片展示；默认每个文件夹生成一个同名作品，可把多个文件夹（如 mp3 版 / wav 版）归入同一作品，点进作品显示内部子文件夹以选择格式。
- **虚拟文件夹系统**：镜像物理磁盘目录树，文件夹名 = 真实文件夹名，支持重命名 / 移动 / 删除（仅虚拟，不动磁盘文件）。
- **字幕智能匹配**：`a.mp3` → `a.mp3.vtt` 优先 → `a.vtt`（同名去扩展名），并支持 `.srt` / `.lrc`；可随时一键「替换字幕」。
- **字幕模式**：模糊封面背景 + 逐行歌词，自动滚动跟随播放、当前句高亮，上下滑动浏览、点击歌词跳转到对应乐句。
- **封面**：自动读取内嵌封面 / 同目录 `cover.*` 图，支持自定义导入封面（按作品存储）。
- **标签筛选**：命名空间标签 + AND/OR/NOT 筛选 + 高级布尔表达式，曲目与文件夹均可打标签。
- **播放**：队列、上一首/下一首、进度拖动、循环（列表/单曲）、随机、音量；Android 支持后台播放通知栏（MediaSession 媒体控制）。

## 技术栈

Flutter 3.47 + Provider + sqflite（桌面用 sqflite_common_ffi）+ [flutter_soloud](https://pub.dev/packages/flutter_soloud)（SoLoud 内核，源码随包编译，mp3/wav 解码 + miniaudio 输出，三端统一，无 GitHub 二进制下载）+ [audio_metadata_reader](https://pub.dev/packages/audio_metadata_reader)（元数据/内嵌封面）。

## 目录结构

```
lib/
  db/           数据库表 + DAO（works / folders / tracks / tags）
  services/     扫描、字幕解析、元数据、封面、导入、数据目录、设置
  state/        AppState（库状态）+ PlayerController（播放）
  widgets/      作品网格、文件夹浏览、播放栏、左侧面板、对话框、封面组件
  pages/        主页、字幕模式、设置
  theme/        应用主题（原创深色配色）
  utils/        日志、筛选表达式、时间格式化
```

## 构建

### 一键脚本

| 平台 | 脚本 |
| --- | --- |
| Linux (Ubuntu) | `scripts/build_linux.sh` |
| Windows | `scripts/build_windows.bat` |
| Android（Linux / WSL2） | `scripts/build_android.sh` |
| Android（Windows） | `scripts/build_android.bat` |
| Windows（从 Linux 远程触发） | `scripts/build_windows_remote.sh` |

脚本已内置中国镜像环境变量，直接运行即可（需先安装对应平台工具链）。

> **Android 依赖说明**：`pubspec.yaml` 已配置 `hooks.user_defines.sqlite3.source: system`，让 sqlite3（sqflite_common_ffi 的依赖）使用系统 SQLite 库，避免构建时从 GitHub 下载预编译二进制（国内网络无法访问 GitHub）。Android 端实际使用 sqflite 插件，不依赖该 FFI。

> **注意**：Flutter 不支持 Linux 交叉编译 Windows（报错 `"build windows" only supported on Windows hosts.`）。因此 Windows 版要么在 Windows 上直接运行 `build_windows.bat`，要么用 `build_windows_remote.sh` 通过 SSH 在 Windows 机器上远程构建并回传产物（需 Windows 开启 OpenSSH Server 并装好 Flutter + Visual Studio，详见脚本顶部注释）。

### 依赖镜像（中国网络）

项目已内置中国镜像配置：

- Flutter：`PUB_HOSTED_URL=https://pub.flutter-io.cn`、`FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`
- Android Gradle：阿里云 + 腾讯 Maven 镜像（`android/settings.gradle.kts`、`android/build.gradle.kts`）
- Gradle 发行包：腾讯镜像（`android/gradle/wrapper/gradle-wrapper.properties`）

### Linux（Ubuntu）

依赖：Flutter SDK、cmake / ninja / clang / gtk3（`sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev`）。

```bash
cd MediaShelf
export PUB_HOSTED_URL=https://pub.flutter-io.cn FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
flutter pub get
flutter build linux --release
# 产物：build/linux/x64/release/bundle/mediashelf
```

> 音频输出使用 miniaudio 后端（运行时 `dlopen` ALSA/PulseAudio，无需 `libasound2-dev`），已在 `linux/CMakeLists.txt` 中显式禁用 ALSA 编译后端。

### Windows

在 Windows 上安装 Flutter + Visual Studio（含「使用 C++ 的桌面开发」），然后：

```bat
cd MediaShelf
set PUB_HOSTED_URL=https://pub.flutter-io.cn
set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
flutter pub get
flutter build windows --release
```

音频输出使用 miniaudio（WASAPI），无需额外依赖。

### Android（小米澎湃 OS）

依赖：Flutter SDK、Android SDK（含 NDK + CMake）、JDK 17+。

```bash
cd MediaShelf
export PUB_HOSTED_URL=https://pub.flutter-io.cn FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
flutter pub get
flutter build apk --release
# 或直接连接设备：flutter run
```

- minSdk 24（Android 7.0），兼容小米澎湃 OS（Android 15）。
- 文件夹选择使用 **SAF 系统文件夹选择器**（无需存储权限，用户选择后由系统授权访问）。

## Android 文件访问与后台播放

### 所有文件访问授权

Android 11+ 采用分区存储。MediaShelf 使用「所有文件访问」（`MANAGE_EXTERNAL_STORAGE`）以获得真实文件路径，直接遍历本地音乐目录（与桌面端同一套扫描逻辑）。

- 首次点击「添加文件夹」时，App 会检测授权状态；未授权则跳转到系统「所有文件访问」设置页，用户授权后即可正常导入。
- 桌面端（Windows/Linux）无需任何权限。

### 后台播放通知栏

Android 端内置前台服务（`PlaybackService.kt`）+ MediaSession + MediaStyle 通知：

- 播放时自动启动前台服务，锁屏/后台继续播放，通知栏显示封面/标题/艺术家与播放控制（上一首 / 播放暂停 / 下一首 / 停止）。
- 通知按钮通过 MethodChannel（`mediashelf/playback`）回传 Dart 侧控制 flutter_soloud。
- 首次启动会请求通知权限（Android 13+）。

## 数据存储

数据目录默认在应用文档目录 `AudioShelf/` 下：`audioshelf.db`（库）、`covers/`（封面缓存）、`settings.json`（设置）。可通过 `.datadir` 指针文件迁移位置。

## 说明

- 删除作品/文件夹均为「虚拟」删除，不会删除磁盘上的音频/字幕文件。
- 字幕匹配规则：`a.mp3.vtt` 优先于 `a.vtt`；同一目录内命名风格一致即可被识别。

## 分支与协作

- `master`：开发分支，日常提交推送目标（`git push` 默认推 master）。
- `main`：稳定分支，**仅由维护者通过 PR 从 master 合并**，不接受直接推送。

开发历程、技术决策与跨平台踩坑记录见 [PROJECTLOG.md](PROJECTLOG.md)。

## 许可证

本项目采用 [MIT License](LICENSE)。

第三方依赖许可证见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) —— 全部为宽松许可证（MIT / BSD / Apache / Zlib），无 GPL 类传染性依赖，可自由商用。
