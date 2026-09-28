# MediaShelf

本地媒体管理器，支持 Windows / Linux / Android 三端。以「作品集（专辑）＋虚拟文件夹」方式管理本地音频、图片与视频。音频可播放并配字幕，图片可浏览、阅读、裁剪封面，视频交给外部播放器。

> **现状**：三库（音频 / 图片 / 视频）统一主界面、图片阅读器、卷封面裁剪、收藏选段与外链播放均已落地。测试 422 例通过，`flutter analyze` 0 error。
>
> 施工方案见 [BUILD_GUIDE.md](BUILD_GUIDE.md)。逐阶段记录见 [PROJECTLOG.md](PROJECTLOG.md)。动手步骤见 [PROJECT_STEPS.md](PROJECT_STEPS.md)。

## 功能

### 通用

| 功能 | 说明 |
| --- | --- |
| 三个库 | 音频库、图片库、视频库。顶栏切换，各自记住自己的作品与文件夹树 |
| 作品集（专辑） | 主页以作品卡片展示。默认每个文件夹生成一个同名作品。可把多个文件夹（如 mp3 版 / wav 版）归入同一作品。点进作品直接平铺作品里的媒体，子文件夹从左栏树进入；音频库另给一层入口文件夹，用于选择格式 |
| 虚拟文件夹系统 | 镜像物理磁盘目录树，文件夹名等于真实文件夹名。支持重命名、移动、删除。删除会连子文件夹与其中的媒体记录一起移出软件，磁盘文件不动 |
| 分类标签 | 导入时按媒体类型与扩展名自动打规则标签，形如 `kind:audio`、`ext:mp3`。标签面板可据此筛选 |
| 字幕默认排除 | 字幕照常入库，默认不进列表。排除集随设置持久化，重启后保持 |
| 标签筛选 | 命名空间标签配 AND / OR / NOT 筛选，另支持高级布尔表达式。图片库与视频库都能从工具栏打开筛选面板 |
| 标签管理 | 命名空间可折叠（一键展开 / 折叠全部，状态持久化）。新建标签时命名空间按库里已有的猜，同名标签当场提醒。自建标签可改名、改色、删除，删除前先报会解除多少条关联；规则标签只给折叠，不给改名与删除 |
| 多选与批量 | 长按图片 / 视频磁贴或点曲目工具栏的「多选」进选择模式，选择条支持全选、批量加标签、批量移除标签、从软件移除记录。移除只删库里的记录，磁盘文件不动 |
| 缓存管理 | 内嵌封面缓存与缩略图缓存的用量可见，均可在设置页清理 |

### 音频

| 功能 | 说明 |
| --- | --- |
| 播放 | 队列支持拖动排序、删除、「下一首播放」。播放条含上一首 / 下一首、进度拖动、循环（列表 / 单曲）、随机、倍速、音量。Android 端支持后台播放通知栏 |
| 字幕智能匹配 | `a.mp3` 先找 `a.mp3.vtt`，再找 `a.vtt`（同名去扩展名）。支持 `.vtt`、`.srt`、`.lrc` 三种格式。可一键「替换字幕」 |
| 字幕归属 | 「字幕归属」对话框可改归属音频、设默认字幕、解除归属。多字幕按上次选定、文件名匹配、语言优先级三级排序 |
| 字幕模式 | 模糊封面背景配逐行歌词。自动滚动跟随播放，当前句高亮。上下滑动浏览，点击歌词跳到对应乐句 |
| 封面 | 自动读取内嵌封面与同目录 `cover.*` 图。支持自定义导入封面，按作品存储 |
| 收藏选段 | 播放条「选区」按钮拖动两端定范围并命名保存。选段循环优先级高于单曲循环与列表循环。可跳转、改名、删除 |

### 图片

| 功能 | 说明 |
| --- | --- |
| 网格 / 列表浏览 | 列数可调（2 到 10）。缩略图走磁盘缓存，上限可配 |
| 查看器 | 支持缩放、平移、翻页、幻灯片。阅读器带阅读方向与适配模式 |
| 图片详情 | 可改别名、打标签、旋转、导出、删除、定位到文件夹。批量选择条能全选、加标签、移除标签、从软件移除记录 |
| 卷与阅读进度 | 卷面板显示卷封面与卷内图片，可开始阅读、标记读完。阅读进度按卷持久化，下次从上次那页继续 |
| 卷封面 | 四个自动来源依次为白名单封面图、卷内第一张图、曲目内嵌封面、系列封面。另支持手动指定与归一化裁剪 |

### 视频

| 功能 | 说明 |
| --- | --- |
| 识别与卡片 | 按扩展名识别视频。卡片显示文件名、格式、大小 |
| 列表与搜索 | 作品层平铺作品里的视频，文件夹层列出本层视频。搜索只在视频行里找，不串到音频或图片 |
| 外链播放 | 双击或菜单「用外部播放器播放」。程序把当前文件夹（含子文件夹）或整个作品的视频写成 UTF-8 `m3u8` 播放列表，再交给系统默认播放器 |
| 打标签 | 卡片菜单「标签...」直接为视频挑标签，批量选择条能全选、加标签、移除标签、从软件移除记录。标签筛选与高级筛选对视频同样生效 |
| 平台分派 | Windows 走 `cmd /c start`，Linux 走 `xdg-open` |
| 内建视频播放器 | 仅保留接口（`lib/services/video_launcher.dart` 的平台分派）。未实现内建播放，也不随发行版分发任何播放内核 |

## 技术栈

| 层 | 选型 |
| --- | --- |
| 框架 | Flutter 3.47 + Provider |
| 数据库 | sqflite。桌面端用 sqflite_common_ffi，走系统 SQLite |
| 音频 | [flutter_soloud](https://pub.dev/packages/flutter_soloud)。SoLoud 内核源码随包编译，mp3 / wav 解码加 miniaudio 输出，三端统一，无 GitHub 二进制下载 |
| 元数据 | [audio_metadata_reader](https://pub.dev/packages/audio_metadata_reader)。读取标签与内嵌封面 |
| 图片 | `image` 负责缩略图与裁剪，`exif` 读取照片方向 |
| 其他 | `crypto` 算指纹，`desktop_drop` 支持拖入导入，`fast_gbk` 解码 GBK 字幕 |

## 目录结构

```
lib/
  db/           数据库表与 DAO（works / folders / media / tags / segments / reading_progress）
  services/     扫描、媒体类型判定、字幕解析与归属、元数据、封面、缩略图、导入、数据目录、设置、
                阅读进度、卷封面、选段、播放列表写出、外链播放
  state/        AppState（库状态）与 PlayerController（播放）
  widgets/      作品网格、文件夹面板、图片网格、图片查看器与详情、卷面板、卷封面对话框与裁剪编辑器、
                选段面板、播放栏、队列面板、标签与筛选对话框
  pages/        主页（三库）、字幕模式、设置、关于
  theme/        应用主题（原创深色配色）
  utils/        日志、裁剪数学、筛选表达式、图片缓存、时间格式化
```

## 构建

### 一键脚本

| 平台 | 脚本 | 说明 |
| --- | --- | --- |
| Linux (Ubuntu) | `scripts/build_linux.sh` | 支持 `--mode`、`--clean`、`--no-pub`，带日志 |
| Windows | `scripts/build_windows.ps1` | PowerShell 7+，支持 `-Mode`、`-Clean`、`-NoPub`、`-FlutterBin` |
| Windows（旧入口） | `scripts/build_windows.bat` | 薄包装，转调 `build_windows.ps1` |
| Android（Linux / WSL2） | `scripts/build_android.sh` | 支持 `--mode`、`--split`、`--clean`、`--no-pub` |
| Android（Windows） | `scripts/build_android.bat` | 在 Windows 上直接构建 APK |
| Windows（从 Linux 远程触发） | `scripts/build_windows_remote.sh` | SSH 到 Windows 机器上构建并回传产物 |

三个平台脚本的行为一致：

1. 写入中国镜像环境变量。已设置的变量不覆盖。
2. 把完整输出写进 `<应用根>/logs/*_<时间戳>.log`。
3. 失败时以非零退出码结束，并打印失败命令。

```bash
# Linux，产物在 build/linux/x64/release/bundle/
bash scripts/build_linux.sh --mode release

# Android，产物在 build/app/outputs/flutter-apk/app-release.apk
bash scripts/build_android.sh --mode release --split

# Windows 必须在 Windows 上跑
pwsh -File scripts\build_windows.ps1 -Mode release
```

> **注意**：Flutter 不支持从 Linux 交叉编译 Windows（实测报错 `"build windows" only supported on Windows hosts.`）。

Windows 版有两个办法。

| 办法 | 做法 |
| --- | --- |
| 本机构建 | 在 Windows 上直接跑 `build_windows.ps1` |
| 远程构建 | 用 `build_windows_remote.sh` 通过 SSH 在 Windows 机器上构建并回传产物。需要 Windows 开启 OpenSSH Server，并装好 Flutter 与 Visual Studio。详见脚本顶部注释 |

### sqlite3 与音频库的两个构建要点

| 要点 | 做法 |
| --- | --- |
| sqlite3 用系统库 | `pubspec.yaml` 的 `hooks.user_defines.sqlite3` 写成 `source: system`，另加 `name_windows: winsqlite3`。Linux 用系统 `libsqlite3.so`，Windows 用系统自带的 `winsqlite3.dll`（Win10 以上）。构建过程完全不访问 GitHub |
| 构建脚本的三步核对 | `build_linux.sh` 先探测系统库，把它复制进 `bundle/lib/`，再用 `ldd` 报出仍缺失的库。`build_windows.ps1` 核对 `name_windows` 配置，缺失就直接失败。Android 走 sqflite 插件自带的 SQLite，不用该 FFI |
| NO_XIPH_LIBS=1 | `flutter_soloud` 自带的 `libopus` 在 glibc 2.43 上编译，Ubuntu 24.04 只有 glibc 2.39，不禁用会在运行时加载失败。本应用只播 mp3 / wav，用不到 Xiph 系列编码。Linux 构建脚本已固定导出该变量 |

### 依赖镜像（中国网络）

- Flutter：`PUB_HOSTED_URL=https://pub.flutter-io.cn`、`FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`。
- Android Gradle：阿里云与腾讯 Maven 镜像，见 `android/settings.gradle.kts` 与 `android/build.gradle.kts`。
- Gradle 发行包：腾讯镜像，见 `android/gradle/wrapper/gradle-wrapper.properties`。

### 手工构建

```bash
# Linux：依赖 clang cmake ninja pkg-config libgtk-3-dev libsqlite3-dev
export PUB_HOSTED_URL=https://pub.flutter-io.cn FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn NO_XIPH_LIBS=1
flutter pub get && flutter build linux --release

# Windows：需装 Flutter 与 Visual Studio，含「使用 C++ 的桌面开发」
flutter pub get && flutter build windows --release

# Android：需装 Android SDK 与 JDK 17+
flutter pub get && flutter build apk --release
```

音频输出走 miniaudio 后端。Linux 运行时 `dlopen` ALSA 或 PulseAudio，`linux/CMakeLists.txt` 已显式禁用 ALSA 编译后端。Windows 走 WASAPI。两端都无需额外依赖。

## 平台能力

| 能力 | Windows | Linux | Android |
| --- | --- | --- | --- |
| 音频播放、字幕、标签、选段 | ✅ | ✅ | ✅ |
| 后台播放通知栏 | 无 | 无 | 支持 |
| 图片库、查看器、卷阅读、卷封面裁剪 | ✅ | ✅ | ✅ |
| 视频识别与作品管理 | ✅ | ✅ | ✅ |
| 视频外部播放 | ✅ `cmd /c start` | ✅ `xdg-open` | ✅ `Intent.ACTION_VIEW` + FileProvider |

Android 端由 `MainActivity` 用 `Intent.ACTION_VIEW` 拉起系统播放器。URI 一律由 FileProvider 生成，不用 `file://`。共享目录见 `android/app/src/main/res/xml/file_paths.xml`。设备上需要装一个能放视频的应用。

## Android 文件访问与后台播放

### 所有文件访问授权

Android 11 以上采用分区存储。MediaShelf 使用「所有文件访问」（`MANAGE_EXTERNAL_STORAGE`）以获得真实文件路径。得到路径后直接遍历本地媒体目录，与桌面端同一套扫描逻辑。

- 首次点击「添加文件夹」时，程序检测授权状态。未授权则跳到系统「所有文件访问」设置页。用户授权后即可正常导入。
- 桌面端（Windows / Linux）无需任何权限。
- minSdk 24（Android 7.0），兼容小米澎湃 OS（Android 15）。

### 后台播放通知栏

Android 端内置前台服务（`PlaybackService.kt`）、MediaSession 与 MediaStyle 通知。

- 播放时自动启动前台服务。锁屏与后台继续播放。通知栏显示封面、标题、艺术家，以及上一首 / 播放暂停 / 下一首 / 停止四个按钮。
- 通知按钮通过 MethodChannel（`mediashelf/playback`）回传 Dart 侧，控制 flutter_soloud。
- 首次启动会请求通知权限（Android 13 以上）。

### 视频外链播放

视频不在应用内解码，交给系统播放器。

- 卡片菜单与作品菜单都有「用外部播放器播放」。程序按作品的文件夹生成一份 `m3u8` 播放列表，再把它交给系统。
- MIME 由扩展名给出，认不出时给 `video/*`。对照表在 `lib/services/video_launcher.dart`。
- 文件经 FileProvider 的 `content://` URI 授权给播放器，只授一次读权限。
- manifest 的 `queries` 声明了 `ACTION_VIEW` 与视频 MIME。Android 11 起没有这段声明就查不到播放器。

## 数据存储

数据目录默认在应用支持目录的 `AudioShelf/` 子目录下。各平台分别对应 Windows `%APPDATA%`、Linux `~/.local/share`、Android 应用私有目录。

| 文件或目录 | 内容 |
| --- | --- |
| `mediashelf.db` | SQLite 库，含作品、文件夹、媒体、标签、选段、阅读进度 |
| `covers/` | 封面缓存 |
| `playlist/` | 外链播放写出的 `m3u8` |
| `settings.json` | 设置，含主题、网格列数、视图模式、缓存上限、排除标签 |
| `logs/` | 运行日志 |

目录名沿用 `AudioShelf` 是有意为之：迁移期能直接读到老库。改位置有两个办法。一是在设置页用「迁移数据目录」。二是手工放置 `.datadir` 指针文件。

## 说明

- 删除作品或文件夹均为「虚拟」删除，不动磁盘上的媒体文件。
- 字幕匹配规则：`a.mp3.vtt` 优先于 `a.vtt`。同一目录内命名风格一致就能匹配上。
- `.ass`、`.ssa`、`.ttml`、`.smi` 等格式照常导入，界面显示「该格式暂不支持解析」，不会静默丢弃。
- 图片库遇到 `image` 包不支持的格式（如 HEIC、AVIF）照常入库。界面标记为不可预览，并显示占位图。

## 分支与协作

- `master`：开发分支。日常提交的推送目标，`git push` 默认推它。
- `main`：稳定分支。**仅由维护者通过 PR 从 master 合并**，不接受直接推送。
- CI：`.github/workflows/ci.yml`。push 与 PR 都跑，固定 Flutter 3.47.5，先装 `libsqlite3-dev`，再跑 `flutter analyze --no-fatal-infos` 与 `flutter test`。

开发历程、技术决策与跨平台踩坑记录见 [PROJECTLOG.md](PROJECTLOG.md)。

## 许可证

本项目采用 [MIT License](LICENSE)。

第三方依赖许可证见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。全部为宽松许可证（MIT / BSD / Apache / Zlib），无 GPL 类传染性依赖，可自由商用。
