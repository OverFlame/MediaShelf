# MediaShelf 工程日志

只追加，不修改历史条目。
每条写日期、目标、动作、验证。

## 2026-09-27 建项目目录与合并施工指南

目标：为合并 AudioShelf 与 PictureViewer2 定下项目名与施工指南。

动作：

1. 勘察两个仓库，记录目录、模块、依赖、数据库与测试事实。
2. 用 ask_user_question 确认五项决策：项目名、骨架、数据库、平台、视频范围。
3. 新建本目录，写入 BUILD_GUIDE.md。

验证：

- 项目名 MediaShelf 经用户确认。
- BUILD_GUIDE.md 内 33 条 path:line 引用逐条核对，文件存在且行号不超实际行数。
- 附录 16.1 与 16.2 的 64 个文件行数逐条比对实际行数，两份合计 7566 与 10805 一致。
- 测试用例数实测：AudioShelf 72，PictureViewer2 127。
- ste-lint-zh 结果：per100c 0.00，dash 0，shape 0。

未完成事项：目录内只有文档，尚无代码。
下一步：按 BUILD_GUIDE.md 第 11 节的阶段 0 建仓改名。

## 2026-09-27 阶段 0 建仓与改名

目标：把 AudioShelf 骨架迁进 MediaShelf，改掉所有旧名字，跑通三条验收。

动作：

1. 用 rsync 从 AudioShelf 迁入 110 个受控文件。排除 `.git/`、`build/`、`.dart_tool/`、`docs/`、`PROJECT_LOG.md`。
2. 删掉旧 `.git`，重新 `git init`，分支 master。加 remote `git@github.com:OverFlame/MediaShelf.git`，本轮不推送。
3. 按 BUILD_GUIDE 第 3 节改名。清单见下表。

| 位置 | 改法 |
| --- | --- |
| `pubspec.yaml:1` | 包名 audioshelf 改 mediashelf |
| `android/app/build.gradle.kts:8` 与 `:19` | 包名改 `com.mediashelf.mediashelf` |
| `android/app/src/main/kotlin/com/audioshelf/audioshelf/` | 目录迁到 `android/app/src/main/kotlin/com/mediashelf/mediashelf/`，两个文件改 package 声明 |
| `lib/services/media_bridge.dart:31` 与两个 Kotlin 文件 | MethodChannel 前缀改 `mediashelf/playback` |
| `android/app/src/main/AndroidManifest.xml:20` | 应用名改 MediaShelf |
| `lib/main.dart` | AudioShelfApp 改 MediaShelfApp，MaterialApp title 改 MediaShelf |
| `lib/pages/home_page.dart:40`、`lib/pages/settings_page.dart:115` | 标题文字改 MediaShelf |
| `lib/utils/log_util.dart:45` | 日志名改 MediaShelf |
| `linux/CMakeLists.txt:7`、`windows/CMakeLists.txt:3` 与 `:7` | 桌面产物名改 mediashelf |
| `linux/runner/my_application.cc`、`windows/runner/main.cpp`、`windows/runner/Runner.rc` | 窗口标题与版本元数据改 MediaShelf |
| 16 个测试文件 | 导入前缀改 `package:mediashelf/` |
| `scripts/` 五个构建脚本 | 项目名与产物路径同步改 |
| `README.md` | 项目名改 MediaShelf，修掉指向 `PROJECT_LOG.md` 的失效链接 |
4. `.gitignore` 补 `/data/` 与 `/logs/`。

保留未改，按用户决定：

- 数据目录名仍用 AudioShelf，见 `lib/services/data_dir_service.dart:30`。理由：迁移期能直接读到老库。
- 库文件名仍用 `audioshelf.db`，见 `lib/services/data_dir_service.dart:22` 与 `lib/db/database.dart:48`。改库名属阶段 2。

阶段验收：

- `flutter pub get` 成功。27 个包有更新，但受约束限制。
- `flutter analyze --no-fatal-infos`：6 条 info，0 error，退出码 0。
- `flutter test`：72 个用例全过，输出 `+72: All tests passed!`。

构建与产物核对：

- `NO_XIPH_LIBS=1 flutter build linux --release` 成功。产物是 `build/linux/x64/release/bundle/mediashelf`，`ldd` 无缺失库。
- `flutter build apk --debug` 成功。产物是 `build/app/outputs/flutter-apk/app-debug.apk`。
- `aapt2 dump badging` 核对 APK：`package: name='com.mediashelf.mediashelf'`、`application-label:'MediaShelf'`、`launchable-activity: name='com.mediashelf.mediashelf.MainActivity'`。
- APK 内部扫描：`classes9.dex` 有 `mediashelf/playback` 与 `com/mediashelf/mediashelf`，`assets/flutter_assets/kernel_blob.bin` 有 `mediashelf/playback` 两处。Dart 与 Kotlin 两侧通道名一致。
- 桌面可执行文件里含 `com.mediashelf.mediashelf` 与 `MediaShelf` 字面量。全树 grep `audioshelf` 后剩余命中只有数据目录名、库文件名与对应的测试断言。

观察，无功能影响：

- Linux release 快照 `build/linux/x64/release/bundle/lib/libapp.so` 里搜不到 `mediashelf/playback` 与 MediaBridge 的全部方法名。对照组原版 AudioShelf 的 Android release 快照里这些串都在。
- 实测现象是 Linux 目标下整块 Android 桥的字面量都不见了。推测 AOT 按目标平台剪枝。桌面路径本就是 no-op，见 `lib/services/media_bridge.dart:23` 与 `:53`。
- 后续排查不要把它当故障。要查通道名就去查 APK 或源码。

未完成事项：

- Windows 构建没跑，需要远端 Windows 机器，见 `scripts/build_windows_remote.sh`。Android release APK 没跑，需要签名配置。
- `LICENSE` 是 MIT 原文。BUILD_GUIDE 第 15 节提到的 BSD 3-Clause 署名问题在这份文件里不存在，待用户复核。
- BUILD_GUIDE 第 13 节要求存储落 `<应用根>/data/`。当前 DataDirService 落在「应用支持目录/AudioShelf」，两者不一致，留到阶段 7 对齐。
- 视频、迁移服务、图片栈等从 BUILD_GUIDE 第 11 节的阶段 2 起继续。

## 2026-09-27 新增项目建议步骤参考

目标：把「怎么动手」收成一份可照着执行的文档，与方案文档分开放。

动作：

1. 新建 `PROJECT_STEPS.md`，347 行。文档分十节，从开工前准备写到每阶段验收。
2. 逐阶段的动作与验收命令抄自 BUILD_GUIDE 第 11 节，不另立标准。
3. `README.md` 的「现状」段加一条链接指向 `PROJECT_STEPS.md`。

验证：

- 文档引用的既有路径逐条核对通过。`tool/migrate_check.dart` 与 `lib/widgets/video_grid.dart` 在文中标注为待新建。
- 版本号对齐 BUILD_GUIDE 第 5.1 节。file_picker 取 12.1.2，sqflite_common_ffi 取 2.4.2+1。
- ste-lint-zh 结果：`words= 1736 total= 0 per100c= 0.00 dash= 0 shape= 0`。

未完成事项：

- 阶段 1 到阶段 9 的状态列仍是「待开始」。每阶段做完回填。

## 2026-09-27 阶段 1 依赖合并

目标：按 BUILD_GUIDE 第 5 节把依赖表落到 `pubspec.yaml`，并定下版本号规则。

动作：

1. `pubspec.yaml:33` 的 Dart SDK 约束从 `^3.12.0` 提到 `^3.12.2`，对齐第 5.1 节。
2. `pubspec.yaml:19` 的版本号从 `1.0.0+1` 改成 `0.2.0+2`。规则见下。
3. 并入 PictureViewer2 的四个依赖：`crypto: ^3.0.7`、`image: ^4.9.1`、`desktop_drop: ^0.4.4`、`exif: ^3.3.0`。
4. 第 5.3 节的 sqlite3 来源写法沿用 AudioShelf 版，阶段 0 已迁入，本轮不动。

版本号规则：

| 段 | 规则 |
| --- | --- |
| 主版本 | 首个可用版本前保持 0 |
| 次版本 | 每完成一个阶段加 1 |
| 修订号 | 阶段内的小修加 1 |
| 构建号 | `+` 后跟阶段序号加 1，与 Android 的 versionCode 对齐 |

阶段 0 记作 `0.1.0+1`，本轮阶段 1 记作 `0.2.0+2`，阶段 9 收尾到 `1.0.0`。版本号只在 `pubspec.yaml` 维护。`windows/runner/Runner.rc:72` 的 `1.0.0` 是非 Flutter 构建的兜底，正常构建走 `FLUTTER_VERSION` 宏。

阶段验收：

- `flutter pub get` 成功，输出 `Changed 9 dependencies!`。
- `pubspec.lock` 严格解析：file_picker 12.1.2、sqflite_common_ffi 2.4.2+1，与第 5.1 节一致。
- `flutter analyze --no-fatal-infos`：6 条 info，0 error，退出码 0。与阶段 0 基线相同。
- `flutter test`：72 个用例全过，输出 `+72: All tests passed!`。

未完成事项：

- 新增的四个依赖要到阶段 4 与阶段 5 才有用，本轮不写调用代码。

## 2026-09-27 媒体类型查找能力实测

目标：给「视频、图片、音乐怎么区分与查找」找实测依据，不靠记忆下结论。

动作：

1. 探明 Linux 上应用实际加载的 SQLite 库，做三组查询对照。
2. 结果写进 BUILD_GUIDE 第 17 节，作为阶段 2 与阶段 5 的设计输入。

验证：

- `which sqlite3` 命中的是 Android SDK 里的 3.50.6，它编译时没开 FTS5，报 `no such module: fts5`。不能拿它当应用环境的证据。
- 应用在 Linux 用系统库 `/usr/lib/x86_64-linux-gnu/libsqlite3.so.0`，版本 3.46.1。ctypes 读到 `sqlite3_libversion()` 也得 3.46.1。
- 该库的编译选项含 `ENABLE_FTS3`、`ENABLE_FTS4`、`ENABLE_FTS5`。建 FTS5 虚表成功，`tokenize='trigram'` 与 `tokenize='unicode61'` 都成功。
- 插入 `本地音乐播放器`、`My Favorite Song`、`cover.jpg` 后的命中行数：

| 查询 | unicode61 | trigram | LIKE |
| --- | --- | --- | --- |
| 音乐 | 0 | 0 | 1 |
| 播放器 | 0 | 1 | 1 |
| 音乐播放 | 0 | 1 | 未测 |
| avorit | 0 | 1 | 1 |
| favorite | 1 | 1 | 未测 |
| favor* | 1 | 1 | 未测 |

- 复现方式：`python3` 建两张 FTS5 虚表，分别用 `unicode61` 与 `trigram`，插入同三行后逐条 `MATCH` 计数。python3 的 sqlite3 模块链接的就是系统库，版本号与 `sqlite3_libversion()` 一致。

未完成事项：

- Windows 的 winsqlite3.dll 与 Android 的系统 SQLite 是否带 FTS5 还没验。阶段 2 做运行时探测，失败就退回 `LIKE`。
