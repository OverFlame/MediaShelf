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

## 2026-09-27 分支与推送口径

目标：把远端分支结构与推送方式记下来，后续不用再试。

动作：

1. 建远端 `main`，指向阶段 0 提交 `8a4f6f4`，与当时的 `master` 同点。
2. 推 `master` 到阶段 1 提交 `8e63c4f`。

口径：

| 分支 | 用途 |
| --- | --- |
| `master` | 日常开发提交，由我直接推 |
| `main` | 由用户把 `master` PR 进来，我不直接推 |

这条口径与 AudioShelf 一致。实测那边的 `origin/main` 领先 `origin/master` 五个提交，其中一个提交是 `Merge branch 'master' into main`。

验证：

- `git ls-remote --heads origin`：`main` = 8a4f6f4，`master` = 8e63c4f。
- `git rev-list --left-right --count origin/master...master` = `0  0`。
- 推送走 SSH 22 端口。实测 `github.com:443` 不通，本机没有可用代理。SSH 连接 rtt 221ms、delivery_rate 约 45 kbps。推送要放后台跑，不能按默认超时处理。

未完成事项：

- `main` 是代建的。想自己重建就先 `git push origin --delete main`，再自建。

## 2026-09-27 分类查找与库归属决策

目标：回答「用标签做分类查找」的疑问，把决定固化成口径。

背景：用户想复用 tag 机制做分类筛选，导入时自动打类别标签。用户要求先答疑问、先别动手，所以先只做勘察。

勘察结论：

- tags 表两边逐字段同构（MediaShelf/lib/db/tables.dart:65 对 PictureViewer2/lib/db/tables.dart:33），合并成 media_tags 时标签数据零成本迁移。
- ImportService 完全不碰标签（lib/services/import_service.dart:32），自动打标是全新逻辑。
- 字幕与封面只存列不存行（lib/db/tables.dart:56 与 :57），要打标签必须先升格成 media 行。
- 音频导入遇无音频目录就整个返回（lib/services/import_service.dart:68），会连带丢掉同目录的图片。
- getByPath 与 ensureByPath 按路径反查取 id 最小者，命中后改写 parent 与 work_id（lib/db/folder_dao.dart:195 与 :214）。不带库条件，两棵树会互相抢节点。唯一索引建在 (folder_id, path) 上（lib/db/tables.dart:37），允许同一路径挂到多个文件夹。

用户决定：

| 项 | 决定 |
| --- | --- |
| kind 与 ext 标签 | 规则标签，只放定义不写关联行 |
| 字幕默认不显示 | 默认进 notTagIds，状态持久化 |
| 库归属 | folders.library 列，以后可升 libraries 表 |
| 同一目录多库并存 | 允许 |
| 剧集树 | 一季一个文件夹，一集一个文件，总剧集文件夹可有可无 |
| 字幕跨目录 | 默认同目录，允许手动指定，全库扫描由用户发起并确认结果 |
| 全库类型视图 | 做 |
| 封面候选 | 放宽到作品根下整棵子树 |
| 视频剧集 | 复用 works 加 library 列 |

动作：

| 处 | 改动 |
| --- | --- |
| 第 7.1 节 | 决策补两处，media_type 改成四值含 subtitle |
| 第 7.3 节 | DDL 加 ext、name_lower、folders.library、works.library，差异清单加六行 |
| 第 8.3 节 | 改成 library 方案，作废「图片库」合成根 |
| 第 11 节 | 阶段 2 动作补到 5 条，阶段 4、5、6 各补一句 |
| 第 15 节 | 登记远端仓库已定 |
| 第 18 节 | 新增，共七小节 |

验证：

- 13 处替换逐条断言命中一次。BUILD_GUIDE 从 1161 行到 1255 行。
- ste-lint-zh --shape：BUILD_GUIDE.md 7161 字 0/0/0，PROJECT_STEPS.md 1940 字 0/0/0。

未完成事项：

- 阶段 2 的代码还没动，本轮只到指南与步骤文档。

## 2026-09-27 阶段 2 数据层统一

目标：把 tracks 与 images 合并成 media 单表。folders 与 works 加 library 列，标签解析器认识 kind 与 ext 规则标签。

动作：

| 处 | 改动 |
| --- | --- |
| lib/db/tables.dart | 重写成 v5：media 四值、ext 与 name_lower、六个索引、works.library、folders.library、folder_paths 默认递归 |
| lib/db/media_dao.dart | 新建：MediaType、MediaItem、MediaDao，统一写入口 |
| lib/db/track_dao.dart | 读走只读视图 tracks，写走 media，播放历史改 media_id |
| lib/db/tag_dao.dart | 关联表改 media_tags 与 media_id，加 kind 与 ext 规则标签 |
| lib/utils/filter_expression.dart | 改用 IN 与 NOT IN 收窄 |
| lib/db/folder_dao.dart | create 与反查带 library 条件，默认 audio |
| lib/db/work_dao.dart | Work 带 library，listAll 可按库过滤 |
| lib/db/database.dart | 库文件名改 mediashelf.db |
| pubspec.yaml | 版本改 0.3.0+3 |

验证：

- flutter analyze --no-fatal-infos：6 条 info，0 error，与阶段 0 基线逐条相同。
- flutter test：75 用例全过，阶段 0 与阶段 1 的基线是 72。
- 新用例断言 PRAGMA integrity_check 返回 ok。覆盖 media 四值、两个 CHECK、路径唯一与视图只读。
- 另覆盖 folder_paths 默认递归、规则标签翻译与外键级联。
- ste-lint-zh --shape：PROJECTLOG.md 2718 字 0/0/0，PROJECT_STEPS.md 2013 字 0/0/0，BUILD_GUIDE.md 7161 字 0/0/0。

踩坑：

- SQLite 不接受括号里的复合查询当集合运算操作数，`(SELECT ...) INTERSECT (SELECT ...)` 报 near "INTERSECT" 语法错。改成音频作用域加 IN 与 NOT IN。
- 指南第 11 节的验收命令 `flutter test test/db` 指向不存在的路径，test 下是平铺文件。改成跑全量 `flutter test`。

未完成事项：

- 老库迁移在阶段 8，过渡视图 tracks 与 images 到阶段 6 结束前删除。
- 三入口导入、卡片样式与全库类型视图从阶段 3 起做。

## 2026-09-27 音频「系列与卷」定稿

目标：用户有同系列有声小说，分卷发售。每卷带特典音声、特典图片与自家封面。要求先给方案，本轮不动代码。

发现：

- `works` 表平铺无父级，音频侧语义是专辑，一个作品已能装多个一级文件夹。
- `folders` 表没有 `cover_path`，也没有 `sort_order`，卷封面无处安放。
- 导入时把导入根目录也建成文件夹，系列根会多出一层，见 `lib/services/import_service.dart:176`。
- 封面白名单只有七个名字，名字不命中的卷封面选不中，见 `lib/services/file_scanner.dart:127`。

决定：

| 议题 | 决定 |
| --- | --- |
| 层级 | 系列 = works 行，卷 = 该系列下的一级文件夹 |
| 卷封面 | `folders` 加 `cover_path`，自动候选加手动指定覆盖 |
| 特典标记 | 固定子目录名（特典／SP／Bonus）导入时自动打普通标签「特典」 |
| 卷内图片 | 音频库卷详情加「本卷图片」区，按路径前缀查卷子树的 image 行 |

默认口径，用户未否决：导入系列时跳过系列根那一层；卷排序暂不加 `sort_order`，名字带卷号够用。

落点：文档写进 BUILD_GUIDE 第 19 节，并同步第 18.6 与 18.7 节的指向。代码实现放阶段 4，与图片入口一起做。阶段 3 迁移服务不受影响。

验证：

- 本轮只改文档。`flutter analyze --no-fatal-infos` 仍是 6 条 info、0 error，`flutter test` 仍是 75 用例全过。
- ste-lint-zh --shape：BUILD_GUIDE.md 7829 字 0/0/0，PROJECT_STEPS.md 2048 字 0/0/0，PROJECTLOG.md 3534 字 0/0/0。

未完成事项：`folders.cover_path` 的 v6 增量、卷封面 DAO 与手动指定、系列导入入口。另有特典自动标签与卷内图片区。等用户放行后开工。

## 2026-09-27 三种媒体组织形式与改进（决策）

背景：用户提出多卷漫画，要求我自己盘点三种媒体的形态。本轮只读勘察。

发现：

| 处 | 问题 |
| --- | --- |
| `lib/db/tables.dart:16` | `works.library` 的 CHECK 只有 audio 与 video，图片系列建不了 |
| `lib/services/file_scanner.dart:9` | 音频只认 .mp3 与 .wav，FLAC、M4A、AAC、OGG、OPUS 全扫不到 |
| `PictureViewer2/lib/services/file_scanner.dart:6-9` | 图片 9 个扩展名，缺 HEIC 与 AVIF |
| `PictureViewer2/lib/db/image_dao.dart:302-317` | 排序键只有五个，全走 COLLATE NOCASE，没有自然排序 |
| `lib/state/app_state.dart:228-231` | 作品层把条目写死成空列表，电影系列无处安放 |
| `media` 列 | 无拍摄日期、无页序、无阅读进度 |
| `play_history` | 只有播放时间，没有看到第几分钟 |

决定：

| 议题 | 决定 |
| --- | --- |
| 漫画多卷 | 系列 = works（library 加 image），一本 = 一级文件夹 |
| 自然排序 | `media` 加 `sort_key` 列，数字补零后排序，三边共用 |
| 扩展名 | 音频补 FLAC／M4A／AAC／OGG／OPUS，图片补 HEIC／AVIF |
| 作品层 | 允许作品下直接放条目，用途是电影系列、单卷散图与单曲作品 |

后置：压缩包识别、EXIF 拍摄日期列、阅读与观看进度、特典名字表可配。

不做：整轨 cue 分轨、BDMV 原盘折叠、跨页合并显示、跨媒体系列、古典乐多创作者元数据。

落点：v6 增量与阶段 4 一起做，作品平铺条目在阶段 6。文案落在 BUILD_GUIDE 第 20 节，并同步第 18.6 节的图片入口指向。

验证：

- 本轮只改文档。`flutter analyze --no-fatal-infos` 仍是 6 条 info、0 error，`flutter test` 仍是 75 用例全过。
- ste-lint-zh --shape：BUILD_GUIDE.md 8399 字 0/0/0，PROJECT_STEPS.md 2076 字 0/0/0，PROJECTLOG.md 3534 字 0/0/0。

未完成事项：以上四条决定的代码实现，等用户放行。

