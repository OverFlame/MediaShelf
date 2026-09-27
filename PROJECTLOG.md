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
