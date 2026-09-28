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
- ste-lint-zh --shape：BUILD_GUIDE.md 7829 字 0/0/0，PROJECT_STEPS.md 2048 字 0/0/0，PROJECTLOG.md 3127 字 0/0/0。

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

## 2026-09-27 封面裁剪与图片侧自定义封面（决策）

需求：用户要求封面支持自定义裁剪显示范围。图片侧同样支持自定义封面。本轮只改文档。

决定：

| 议题 | 决定 |
| --- | --- |
| 裁剪存储 | `works` 与 `folders` 各加 `cover_crop` 列，存归一化的左、上、右、下四个数 |
| 显示算法 | 按目标区宽高比把裁剪框扩成同比例，中心不变，超出原图向内收 |
| 原图 | 永不改动，裁剪只影响渲染 |
| 图片侧 | 系列封面落 `works.cover_path`，卷封面落 `folders.cover_path`，与音频共用一套方法 |
| 交互 | 封面菜单加自定义裁剪与恢复默认；网格按卡片比例裁，详情页看全图 |

落点：存储与算法在阶段 4，交互与显示在阶段 6。文案落在 BUILD_GUIDE 第 21 节，并同步第 19.2 与 20.5 节的指向。

验证：

- 本轮只改文档。`flutter analyze --no-fatal-infos` 仍是 6 条 info、0 error，`flutter test` 仍是 75 用例全过。
- ste-lint-zh --shape：BUILD_GUIDE.md 8793 字 0/0/0，PROJECT_STEPS.md 2085 字 0/0/0，PROJECTLOG.md 3854 字 0/0/0。

踩坑：

- 同步 lint 数字时用了全局正则，把两条历史条目的数字一起改了。改用行内唯一锚点重做。

未完成事项：`cover_crop` 列、裁剪算法与用例、封面菜单交互，等用户放行。

## 2026-09-27 漫画阅读模式（决策）

需求：用户问能否内置漫画阅读器。本轮只做日漫左右翻页，上下滚动不做。

发现：

| 项 | 事实 |
| --- | --- |
| 查看器基础 | `PictureViewer2/lib/widgets/image_viewer.dart` 已有缩放、键盘、相邻预载、降采样与缓存上限 |
| 阅读方向 | 现为左右键固定语义，`PictureViewer2/lib/widgets/image_viewer.dart:279` |
| 适应模式 | 写死 `BoxFit.contain`，同文件 `:397` |
| 双页并排 | 无 |
| 阅读进度 | 无，第 20.7 节原列为后置 |
| HEIC 与 AVIF | `image` 4.10.1 无解码器，扫描覆盖率与显示能力不一致 |

决定：

| 议题 | 决定 |
| --- | --- |
| v1 范围 | 全屏无干扰、左右翻页、方向切换、适应模式循环 |
| 阅读方向 | 记在卷，`folders.reading_direction`，默认 `rtl` |
| 适应模式 | 记在卷，`folders.reading_fit`，默认 `page` |
| 双页并排 | 显示后置，存储按 `reading_spreads` 表在 v6 预留 |
| 阅读进度 | 随阶段 6 做，`reading_progress` 表 |
| HEIC 与 AVIF | 照常入库，界面标注「不可预览」 |

口径：第 22.5 节按预留存储理解持久化要求。若要在 v1 就支持单对页并排显示，落点需调整。

落点：阅读器核心与 v6 增量在阶段 4，阅读进度与卷层入口在阶段 6。文案落在 BUILD_GUIDE 第 22 节，并同步第 15 节未决项、第 20.3、20.6 与 20.7 节。

验证：

- 本轮只改文档，代码零改动。
- ste-lint-zh --shape：BUILD_GUIDE.md 9822 字 0/0/0，PROJECT_STEPS.md 2157 字 0/0/0，PROJECTLOG.md 4227 字 0/0/0。

未完成事项：阅读器改造、v6 增量、阅读进度与入口都未实现，等用户放行代码。

## 2026-09-27 字幕格式与编码（决策）

需求：用户问字幕是否支持 LRC 等常见格式，要求复查对常见格式的支持度。

发现：

| 项 | 事实 |
| --- | --- |
| 白名单 | 只认 `.vtt` `.srt` `.lrc`，见 `lib/services/file_scanner.dart:12` |
| 解析分派 | 只有三个分支，其余静默返回空，见 `lib/services/subtitle_parser.dart:43` |
| GBK 乱码 | 探针实测 UTF-8 解码抛 `FormatException`，退 latin1 后中文成乱码 |
| `[offset:±ms]` | 探针实测正则零命中，整体校准没有生效 |
| 纯文本 LRC | 探针实测零行命中，界面只显示「无字幕」 |
| 语言后缀 | `a.chs.srt` 匹配不到 `a.mp4`，见 `lib/services/file_scanner.dart:97` |
| ASS 与 SSA | 不在白名单也不在解析分派，动漫字幕主要格式落空 |
| BOM | 探针确认 Dart 的 UTF-8 解码器自己剥离，无需处理 |

决定：

| 议题 | 决定 |
| --- | --- |
| 编码 | 加 `fast_gbk` 依赖，探测链 UTF-8 到 GBK 到 latin1 |
| 格式 | ASS 与 SSA、TTML 与 DFXP、SMI 与 SAMI 只准备接口，解析留空 |
| LRC | `[offset:±ms]` 生效，纯文本歌词兜底 |
| 匹配 | 补语言后缀、大小写不敏感、一个媒体挂多条字幕 |

口径：占位格式进 `knownSubtitleExtensions` 但不进 `subtitleExtensions`。文件能扫到并入库，界面标注「该格式暂不支持解析」，与 HEIC 的不可预览口径一致。

落点：解析与匹配在阶段 4，归属模型与界面在阶段 6。文案落在 BUILD_GUIDE 第 23 节，并同步第 18.5 与 18.7 节。

验证：

- 本轮只改文档，代码零改动。
- ste-lint-zh --shape：BUILD_GUIDE.md 10671 字 0/0/0，PROJECT_STEPS.md 2224 字 0/0/0，PROJECTLOG.md 4631 字 0/0/0。

未完成事项：fast_gbk 依赖、注册表、编码链、LRC 增强、匹配规则与两列归属模型都未实现，等用户放行代码。

## 2026-09-28 阶段 3 迁移服务

目标：把 AudioShelf 与 PictureViewer2 两个老库并成一个 mediashelf.db。

动作：

| 文件 | 内容 |
| --- | --- |
| `lib/services/media_rules.dart` | 新建。扩展名白名单与路径归一化的唯一来源，纯 Dart |
| `lib/services/migration_service.dart` | 新建。跨库只读 SELECT，目标库单事务写入 |
| `lib/services/migration_check.dart` | 新建。五类断言 |
| `tool/migrate.dart` | 新建。迁移命令行入口 |
| `tool/migrate_check.dart` | 新建。校验命令行入口 |
| `tool/migrate_args.dart` | 新建。参数解析，支持 `--x V` 与 `--x=V` |
| `test/services/migration_fixtures.dart` | 新建。两个老库的 DDL 与样本数据 |
| `test/services/migration_service_test.dart` | 新建。5 个用例 |
| `test/services/migration_check_test.dart` | 新建。4 个用例 |
| `lib/services/file_scanner.dart` | 改。扩展名规则改为转发 media_rules.dart |
| `lib/db/media_dao.dart` | 改。`extOf` 与 `nameLowerOf` 转发 media_rules.dart |
| `pubspec.yaml` | 改。加 `sqflite_common: ^2.5.11` |

关键决定：

| 议题 | 决定 | 理由 |
| --- | --- | --- |
| 工具能否脱离 Flutter | 能。service 与 tool 不 import Flutter | 探针实测 `dart run` 下 sqflite_common_ffi 可用 |
| 扩展名规则放哪 | 单独拆 `media_rules.dart` | 迁移与扫描共用一份，纯 Dart 可跑 |
| 同一路径两库都有 | 保留先到者，记入 duplicatePaths | 避免迁移中止，校验时单独报数 |
| 老库缺表 | 跳过并记入 skippedTables | 缺表老库不影响其余数据 |
| 备份 | 默认开，`--no-backup` 可关 | 迁移前先留副本 |

验证：

- `flutter analyze --no-fatal-infos`：6 issues，0 error，6 条 info 与基线逐条相同。
- `flutter test`：84/84 全过。基线 75，本轮新增 9 条。
- 端到端：临时夹具两库迁出 5 行 media，`migrate_check` 五项全 PASS。
- 端到端：重复迁移时服务抛 `StateError`，退出码 1。
- 端到端：真实空图片库加 AudioShelf 夹具迁出 2 行，五项全 PASS。

未完成事项：迁移入口还未接进应用界面。Android 老库路径未验证。图片库的真实数据为零，多卷漫画场景要等用户真实库。

## 2026-09-28 播放增强定稿（第 24 节）

需求：评估四项播放能力的难度。硬约束是不引入商业许可风险。

分析结论：

| 功能 | 难度 | 工期 | 新增依赖 | 结论 |
| --- | --- | --- | --- | --- |
| 1 播放模式补全 | 低 | 1 到 2 天 | 无 | 先做 |
| 2 收藏选段 | 低到中 | 2 到 3 天 | 无 | 第三做 |
| 3 外链播放列表 | 低到中 | 1 到 2 天 | 无 | 第二做 |
| 4 内置视频播放器 | 高 | 3 到 6 天 | 待定 | 后置 |

许可证核实：

| 组件 | 许可证 | 证据 |
| --- | --- | --- |
| flutter_soloud 4.1.7 | MIT | 包内 LICENSE |
| media_kit 1.2.6 | MIT | 包内 LICENSE，README 不提 libmpv |
| 预编译 libmpv | 未定 | Windows 库包下载 7z，构建选项未知 |
| libvlc | GPL-2.0+ | VideoLAN 官方 FAQ |
| PotPlayer / VLC 进程调用 | 无 | 不产生链接 |

决定：

| 议题 | 决定 |
| --- | --- |
| 实施顺序 | 先做功能 1、功能 3、功能 2 |
| 功能 4 | 后置，等 libmpv 许可证定案 |
| 选段形态 | A-B 区间循环加书签跳转，两者都做 |
| 文档 | 写成 BUILD_GUIDE 第 24 节加本条记录 |

落点：第 24 节把三项排为阶段 10 到 12，插在阶段 4 之前。改动集中在播放层，与数据层重构不冲突。

验证：

- 本轮只改文档，代码零改动。
- `flutter analyze --no-fatal-infos` 与 `flutter test` 数字不变。
- ste-lint-zh --shape：三份文档 0/0/0。

未完成事项：功能 4 后端未定案。PotPlayer 与 VLC 的多文件参数待真机实测。功能 1、3、2 的代码未动。

## 2026-09-28 阶段 10 播放模式补全

目标：补齐播放模式、队列编辑与播放速度，设置随重启回读。

动作：

| 文件 | 改动 |
| --- | --- |
| `lib/state/player_controller.dart` | 洗牌改成整轮排列，加队列编辑、速度控制与三个模式回调 |
| `lib/services/settings_service.dart` | 加 `repeat_mode_name`、`shuffle`、`play_speed` 三键 |
| `lib/state/app_state.dart` | 接三个持久化回调，加连播入口 `playFolderAll` 与 `playWorkAll` |
| `lib/widgets/queue_panel.dart` | 新建，底部弹层支持拖动排序、点按跳转与移除 |
| `lib/widgets/player_bar.dart` | 加速度按钮、速率对话框与队列按钮 |
| `lib/widgets/folder_browser.dart`、`lib/widgets/works_grid.dart` | 菜单加「播放全部」 |
| `test/state/player_controller_test.dart` | 新建，17 条用例 |
| `test/settings_service_test.dart` | 加 1 条播放设置回读用例 |

关键决定：

| 议题 | 决定与理由 |
| --- | --- |
| 洗牌算法 | 洗成整轮排列。旧实现每次随机取一首，会连续重复同一首 |
| 队列重排口径 | 用移除之后的下标，与 `ReorderableListView.onReorderItem` 对齐 |
| 引擎未初始化 | `_loadAndPlay` 直接返回。队列逻辑因此能脱开原生库跑用例 |
| 回读不写回 | `loadSettings` 里加 `_loadingSettings` 闸门，避免回读触发保存 |
| 枚举重名 | `RepeatMode` 与 Flutter 同名枚举冲突，material 导入加 `hide RepeatMode` |
| 功能 4 | 只留接口。用户说了再做，且不分发 |
| 版本号 | 阶段 3 漏改版本号，本轮补到 `0.5.0+10` |

验证：

- `flutter analyze --no-fatal-infos`：6 条 info，0 error，与阶段 0 基线逐条相同。
- `flutter test`：102 用例全过，阶段 3 的基线是 84。
- 提交 `a7ce52d`。

未完成事项：Windows 与 Android 真机验收未做。功能 3 与功能 2 未开始。

## 2026-09-28 阶段 11 外链播放列表

目标：把剧集与卷交给系统默认播放器，用 m3u8 播放列表承载多文件。

动作：

| 文件 | 改动 |
| --- | --- |
| `lib/services/playlist_writer.dart` | 新建。写 UTF-8 的 m3u8，落数据目录 `playlist/` |
| `lib/services/video_launcher.dart` | 新建。按平台分派 `cmd /c start` 与 `xdg-open` |
| `lib/db/media_dao.dart` | 加 `queryByDirs`，按目录前缀分批取媒体行 |
| `lib/state/app_state.dart` | 加 `playFolderExternal`、`playWorkExternal` 与路径收集 |
| `lib/widgets/launch_result_snack.dart` | 新建。把启动结果转成提示条 |
| `lib/widgets/folder_browser.dart`、`lib/widgets/works_grid.dart` | 菜单加「用外部播放器播放」 |
| `test/services/playlist_writer_test.dart` | 新建。4 条用例 |
| `test/services/video_launcher_test.dart` | 新建。5 条用例 |

关键决定：

| 议题 | 决定与理由 |
| --- | --- |
| 平台分派写法 | 放纯函数 `VideoLauncher.commandFor`。用例不用起进程就能断言命令 |
| 打开失败 | 返回 `failed`，提示条指向 logs 目录，不抛异常 |
| 目录取行 | 整棵文件夹树 BFS 收路径，再按 `path LIKE` 前缀取行，不按 `folder_id` 关联 |
| 条目顺序 | 按 `filename` 排序，与界面显示一致 |
| 视频优先 | 目录内有视频时只写视频，否则写目录内全部媒体 |
| 引擎范围 | 外链播放不碰应用内音频引擎，与 v1 视频范围一致 |

验证：

- `flutter analyze --no-fatal-infos`：6 条 info，0 error，与阶段 0 基线逐条相同。
- `flutter test`：111 用例全过，阶段 10 的基线是 102。
- 提交 `7dc6c75`，`pubspec.yaml` 版本号改 `0.6.0+11`。

未完成事项：Windows 真机未验。三项待实测：PotPlayer 与 VLC 传多文件的参数；含空格路径给 `start` 加引号；VLC 的 `--playlist-enqueue`。Android 走 Intent 加 FileProvider，v1 不做。

## 2026-09-28 阶段 12 收藏选段

目标：把一段区间存成可复用的选段，循环交给引擎区间，不用定时器轮询。

动作：

| 文件 | 改动 |
| --- | --- |
| `lib/db/tables.dart` | 版本升到 6，加 `media_segments` 表与索引，迁移进 `Tables.migrations[6]` |
| `lib/services/segment_service.dart` | 新建。起止收口、优先级判定与增删改查 |
| `lib/state/player_controller.dart` | 加 `_loopSegment` 与 `setLoopSegment`，起播传 `loopingStartAt` 与 `loopingEndAt` |
| `lib/state/app_state.dart` | 加选段列表、增删改与跳转，切歌时顺带载入选段 |
| `lib/widgets/segment_panel.dart` | 新建。底部弹层，两个手柄的 RangeSlider 定范围 |
| `lib/widgets/player_bar.dart` | 加「选区」按钮 |
| `test/services/segment_service_test.dart` | 新建。21 条用例 |
| `test/state/player_controller_test.dart` | 加 5 条段循环用例 |
| `test/widget/segment_panel_test.dart` | 新建。6 条界面点击用例 |

关键决定：

| 议题 | 决定与理由 |
| --- | --- |
| 循环实现 | 用引擎的排他循环区间。首播传边界，播放中改边界调 `setLoopPoint` 与 `setLoopEndPoint` |
| 优先级 | 段循环优先于 `RepeatMode.one`。判定抽成纯函数 `policyOf`，用例直接断言 |
| 松手生效 | `onChanged` 只动手柄，`onChangeEnd` 才把区间交给播放器 |
| 时长口径 | 起止按毫秒存。`normalizeRange` 收口到曲目时长，最短 200 毫秒 |
| 空列表通知 | 列表没变就不通知，避免切歌时多出一次重建 |
| 未初始化守卫 | `_applyLoopPoints` 在没初始化时直接返回。用例因此不碰原生库 |

验证：

- `flutter analyze --no-fatal-infos`：6 条 info，0 error，与阶段 0 基线逐条相同。
- `flutter test`：143 用例全过，阶段 11 的基线是 111。
- 提交 `95f2150`，`pubspec.yaml` 版本号改 `0.7.0+12`。

未完成事项：Windows 与 Android 真机未验。界面用例按桌面宽屏尺寸跑。窄屏下「选区」按钮与队列按钮一起收进溢出菜单，未覆盖。

## 2026-09-28 界面点击验收（阶段 11 与 12）

目标：两个阶段的功能按真实按钮点击走一遍，不只看单元测试。

动作：

| 文件 | 改动 |
| --- | --- |
| `test/widget/external_play_menu_test.dart` | 新建。3 条点击用例：卷菜单、空卷失败提示、作品卡片菜单 |
| `test/widget/segment_panel_test.dart` | 阶段 12 建的 6 条点击用例：保存、拖手柄、松手生效、列表四个按钮、清除、播放条开面板 |
| `lib/state/app_state.dart` | 加 `videoLauncher` 注入点，界面用例能看住交付给系统的命令 |
| `lib/widgets/cover_image.dart` | 占位图标的尺寸收成有限值。作品卡片传的是 `double.infinity`，原来会触发断言 |

关键决定：

| 议题 | 决定与理由 |
| --- | --- |
| 假播放器 | 只换 `start` 回调，平台分派与参数拼装仍走真实代码 |
| 真实 I/O 与假时钟 | 每次点击后用 `runAsync` 与 `pump` 交替让出事件循环。单次让出推不动整条链路 |
| 空卷用例 | 卷里没有媒体时断言不拉起播放器，同时验证失败提示条 |
| 封面占位尺寸 | 宽度不是有限值时退回 32。作品卡片本来就传无限宽高 |

验证：

- `flutter analyze --no-fatal-infos`：6 条 info，0 error。
- `flutter test`：146 用例全过，阶段 12 的基线是 143。
- 提交 `91269be`。

未完成事项：窄屏下「选区」与队列按钮收进溢出菜单的形态未覆盖。

## 2026-09-28 阶段 4 数据层与字幕

目标：升 v7 数据层，补自然排序与字幕识别。

动作：

| 文件 | 改动 |
| --- | --- |
| `lib/db/tables.dart` | 版本升到 7。works 的 library 加认 image，加 cover_crop。media 加 sort_key。folders 加 cover_path、cover_crop、reading_direction、reading_fit。新增 reading_spreads |
| `lib/services/media_rules.dart` | 加 `baseNameOfPath`、`naturalSortKey`、`sortKeyOfPath` |
| `lib/db/media_dao.dart` | 加 `sortKey` 字段与 `compareNatural`。查询默认按自然序 |
| `lib/services/subtitle_parser.dart` | 结果改 `SubtitleDocument`。加 UTF-8、GBK、latin1 的探测链。LRC 的 `[offset:]` 生效，纯文本歌词不再整篇丢 |
| `lib/services/file_scanner.dart` | 字幕匹配改多值，按四档优先级排队。语言标记认 zh-CN、简日、CHS&JPN |
| `lib/services/import_service.dart` | 先取优先级最高的一条字幕，多字幕归属留阶段 6 |
| `lib/state/app_state.dart` | `getSubtitleLines` 换成 `subtitleFor`，返回 `SubtitleDocument` |
| `lib/pages/subtitle_page.dart` | 占位格式显示提示。无时间标签的歌词整篇静态显示 |
| 迁入 7 库 + 6 测试 | sql_like、path_util、file_io、color_util、image_cache_util、thumbnail_cache、exif_service |
| `pubspec.yaml` / `THIRD_PARTY_NOTICES.md` | 加 `fast_gbk ^1.0.0`。通知文件补五项依赖与署名表 |

关键决定：

| 议题 | 决定与理由 |
| --- | --- |
| 版本号口径 | folders.cover_path 原定 v6，阶段 12 已把 v6 用给 media_segments。阶段 4 走 v7，字幕归属列留给阶段 6 的 v8 |
| 重建父表 | SQLite 的 DROP TABLE 会先做一次隐式 DELETE，触发 folders.work_id 的 ON DELETE SET NULL。迁移里先备份 work_id，重建 works 后回填 |
| defer_foreign_keys | 挡不住上面的 SET NULL，这条语句已删掉 |
| 自然排序 | 主干补零到四位，扩展名原样跟后面。第一版把扩展名里的数字也补零，`第10话.mp3` 变成 `第0010话.mp0003` |
| 语言后缀 | 用 `-` 与 `&` 切段。地区词只接在中文系语言词后面。连写汉字按字符判定 |
| 占位格式 | `.ass`、`.ssa`、`.ttml`、`.dfxp`、`.smi`、`.sami` 算字幕文件，但不参与匹配，解析结果带提示 |
| latin1 兜底 | GBK 用 `allowMalformed: true`，畸形字节出替换符且不抛异常。latin1 这一步当前触发不到，保留是为了对齐指南的三级链 |
| 迁入文本的风格 | 迁入文件里的 8 个破折号字符保持原样。它们属于迁入文本，中文文档检查器不扫 Dart 代码 |

验证：

- `flutter analyze --no-fatal-infos`：5 条 info，0 error。字幕解析器重写后，原来的 `unintended_html_in_doc_comment` 消失。
- `flutter test`：231 用例全过。阶段 12 的基线是 146，迁入的 6 个测试文件贡献 64 条，本轮新增与改写 21 条。
- 提交 `1cb94aa`。

未完成事项：占位字幕当前只扫得到、还没入库，归属模型与入库随阶段 6 落地。

## 2026-09-28 阶段 4-8 合并落地（图片栈、字幕归属、视频识别、统一界面与设置、打包脚本）

动作：

| 范围 | 落地内容 |
| --- | --- |
| 数据层 | tables 升到 v8。`media` 加 `subtitle_of`、`is_default_subtitle` 与索引；新增 `reading_progress` 表 |
| 图片栈迁入 | 迁入 sql_like、path_util、file_io、color_util、image_cache_util、thumbnail_cache、exif_service 七个库与配套用例 |
| 阅读器 | 新建 `image_viewer`、`image_detail`、`image_grid`、`folder_panel`、`crop_math`、`reading_progress_service`、`volume_cover_service`、`volume_panel`、`cover_crop_editor`、`volume_cover_dialog` |
| 字幕 | 新建 `subtitle_service` 与 `subtitle_assign_dialog`。字幕按 `subtitle_of` 归属到音频，默认字幕三级顺序：上次选定、文件名匹配、语言优先级 |
| 视频 | `media_rules` 加视频扩展名与 `mediaTypeOfPath`。卡片按库分派，双击走 `VideoLauncher` 外链 |
| 统一界面 | 重写 `home_page`：音频、图片、视频三库切换，导航栏切换、面包屑、多选栏、标签筛选与高级筛选 |
| 设置与主题 | 设置页支持主题三档、网格列数、视图模式、缓存上限、数据目录切换与迁移；新建关于页 |
| 打包 | 重写 `scripts/build_linux.sh`、`scripts/build_android.sh`、`scripts/build_windows.bat`，新增 `scripts/build_windows.ps1` |
| 文档 | 重写 README，补功能、构建、平台能力与数据存储四组表格 |

关键决定：

| 议题 | 决定与理由 |
| --- | --- |
| 数据目录名 | 继续用 `AudioShelf`。改名会让用户既有库变孤儿，数据库文件本身叫 `mediashelf.db` |
| 版本号 | 阶段 4 到 8 合并记为 `0.8.0+13`。关于页常量必须同步改 |
| Android compileSdk | desktop_drop 的 android 模块写死 33，它依赖的 androidx 要求 34 以上。根 build.gradle.kts 在子项目评估完之后把 compileSdk 改成 36。AGP 9 只认 compileSdk 属性，也没有 compileSdkVersion 方法 |
| 字幕默认排除 | 规则标签 kind:subtitle 首次启动进 NOT 集并落盘 settings.json，用户改过就不再套用默认值 |
| 左栏布局 | 文件夹面板与标签面板的表头跟列表合并进同一个滚动视图，矮窗口不再顶出溢出条 |
| 假时钟用例 | widget 用例里的真实文件与数据库 I/O 一律放 setUp 或 runAsync。底面板动画要用带时长的 pump 推进 |
| 封面裁剪 | 坐标归一化到 0..1，整幅写成 NULL。取景靠 Positioned 反向偏移，不裁不变形 |

验证：

- `flutter analyze --no-fatal-infos`：5 条 info，0 error。
- `flutter test`：405 用例全过。阶段 12 的基线是 146。
- `scripts/build_linux.sh --mode release`：退出码 0，产物 `build/linux/x64/release/bundle/mediashelf`，系统 sqlite3 已复制进 bundle 的 lib 目录。
- `scripts/build_android.sh --mode release`：退出码 0。产物 `build/app/outputs/flutter-apk/app-release.apk`（71173358 字节）。aapt2 核对：versionName 0.8.0、versionCode 13、compileSdk 36。
- README 过 ste-lint-zh。

未完成事项：Windows 侧构建与运行要用户在本机验证；界面只做过静态与假时钟用例，未跑真机交互。

## 2026-09-28 删除语义改为深度删除（`0.8.1+14`）

用户反馈：删除文件夹后内容变成未归类。期望是从软件数据里移除，磁盘文件不动，删除前有提醒。

动作：

| 项 | 内容 |
| --- | --- |
| 数据层 | `FolderDao.deleteMany(ids)`。一个事务里按深度从深到浅删整棵子树的文件夹行，顺带给集合外的子级置空 parent |
| 状态层 | `AppState` 新增 `deleteFolderDeep`、`deleteWorkDeep`、`countMediaUnderFolder`、`countMediaUnderWork`。内部用 `_expandFoldersDeep`、`_pruneMediaLeftBehind`、`_dropViewerItemsFor` |
| 界面 | 文件夹面板、音频文件夹树、作品卡片三处删除改走深度删除。对话框显示将移除的媒体条数 |
| 版本 | `pubspec.yaml` 升到 `0.8.1+14`，关于页常量同步 |

关键决定：

| 议题 | 决定与理由 |
| --- | --- |
| 旧的浅删保留 | `deleteFolder` 与 `deleteWork` 不动。`test/db_consistency_test.dart` 仍锁浅删语义（子文件夹上移，只清音频孤儿） |
| 跨库吸收 | 删除目录时，如果同一目录也挂在别的库，那边文件夹记录一并移除。否则树里会留下指向空目录的节点 |
| 别处仍覆盖的记录保留 | 清媒体前先看幸存文件夹的路径。还有别处覆盖，就不删。这跟搜索可见性一致 |
| 条数提醒 | 删除前查一次条数写进对话框，删除函数返回实删行数 |

验证：

- `flutter analyze --no-fatal-infos`：5 条 info，0 error。
- `flutter test`：408 用例全过（新增 3 条 `test/state/app_state_delete_test.dart`，阶段 12 基线 146）。
- 新增用例断言三件事：磁盘文件保留，跨库记录移除，删除作品后不留未归类。

未完成事项：Windows 与 Android 未跑真机；对话框只做静态核对。

## 2026-09-28 视觉库列表分层与视频查询分流（`0.8.2+15`）

用户反馈两件事。第一，视频页添加文件夹后，作品下面又多出一个同名文件夹。第二，所有作品都在音频栏里出现。

动作：

| 项 | 内容 |
| --- | --- |
| 作品按库过滤 | `lib/widgets/works_grid.dart` 按 `library` 过滤作品。音频分支改用 `WorksGrid(library: 'audio')`，此前传空值等于不过滤 |
| 库标识 | `AppState` 新增 `currentLibrary` 与 `isVisualLibrary`。`isImageLibrary` 收紧为只认图片库 |
| 视觉库作品层 | 视觉库作品层不再列出入口文件夹，媒体由 `ImageGrid` 平铺。音频库仍列入口文件夹 |
| 媒体类型分流 | 视觉库的文件夹层与搜索按自己的 `MediaType` 查。视频此前落进曲目查询，文件夹层恒为空，搜索也搜不到 |
| 标签筛选类型 | `TagDao` 新增 `getIdsByTags` 与 `getIdsByExpression`。`AppState` 的匹配集合与文件夹过滤改成按当前库类型查 |
| 搜索提示 | 顶栏搜索框提示词按库给。视频库显示「搜索视频...」 |
| 版本 | `pubspec.yaml` 升到 `0.8.2+15`，关于页常量同步 |

关键决定：

| 议题 | 决定与理由 |
| --- | --- |
| 作品层不再画入口文件夹 | 入口文件夹与作品同名。两层磁贴重名，用户看不出哪层是作品。子文件夹从左栏树进 |
| 音频库保留入口文件夹 | 音频作品层靠入口文件夹进专辑与歌单。`FolderBrowser` 直接用 `centerFolders` |
| 筛选按媒体类型查 | 「字幕」kind 标签默认进排除集，筛选因此常开。视频行不在曲目集合里，整层因此为空。这是文件夹层为空的真因 |
| 旧便捷方法保留 | `getTrackIdsByTags` 等留给测试与既有调用，改成通用方法的包装 |

验证：

- `flutter analyze --no-fatal-infos`：5 条 info，0 error。
- `flutter test`：410 用例全过。新增 `test/widget/home_page_test.dart` 视频用例与 `test/state/app_state_images_test.dart` 视频用例。
- 新用例断言四件事。作品层只平铺本库媒体，入口文件夹磁贴不再出现。文件夹层列出本层视频，视频库搜索只命中视频。

未完成事项：Windows 与 Android 未跑真机；视频库的标签筛选未做界面入口。

## 2026-09-28 视频库标签入口（`0.8.3+16`）

用户提出「要加标签」。此前只有音频库有标签面板。图片库靠图片详情与选择条打标签，视频库没有任何入口。

动作：

| 项 | 内容 |
| --- | --- |
| 媒体标签接口 | `AppState` 新增 `setMediaTags` 与 `getTagsForMedia`，另有 `addTagsToMedia` 等通用别名。图片与视频共用 `media_tags` 表 |
| 标签选择框 | `showTagPickerDialog` 新增 `selectedTagIds`，打开时预勾选已有标签 |
| 筛选面板 | `TagPanel` 新增 `filterOnly`。工具栏弹窗只显示标签区，不显示音频导入段与作品集 |
| 视频卡片 | 视频磁贴菜单加「标签...」项，列表视图加同名图标按钮。点选后弹标签选择框 |
| 工具栏 | 图片库与视频库都给出「标签筛选」与「高级筛选」入口，键名带库名 |
| 批量操作 | 选择条的「添加标签」与「移除标签」对视频与图片都显示 |
| 版本 | `pubspec.yaml` 升到 `0.8.3+16`，关于页常量同步 |

关键决定：

| 议题 | 决定与理由 |
| --- | --- |
| 共用 media_tags | 标签表按 media id 存，与媒体类型无关。视频与图片因此不需要新表 |
| 筛选走通用方法 | `_computeMatchingIds` 已按当前库的 `MediaType` 查。视频标签筛选因此自动生效 |
| 保留两个选择框 | `tag_picker_dialog` 与 `dialogs` 里的同名对话框参数不同。本轮只给前者加预勾选，避免动音频分支 |

验证：

- `flutter analyze --no-fatal-infos`：5 条 info，0 error。
- `flutter test`：412 用例全过。新增 `test/widget/home_page_test.dart` 视频标签用例与 `test/state/app_state_images_test.dart` 视频筛选用例。
- 新用例断言三件事。视频库工具栏能打开纯标签面板，卡片菜单能写入标签，AND 与 NOT 筛选对视频生效。

未完成事项：Windows 与 Android 未跑真机。

踩坑：视频磁贴挂着双击手势。测试里单击菜单按钮要等双击判定超时，单靠 `pumpAndSettle` 不会推进那段计时。

## 2026-09-28 阶段 9 Android 外链分派与 CI（`1.0.0+17`）

用户说「完成所有阶段」。此前唯一的未完成项是阶段 9 Android 验收。本轮补齐外链分派与 CI。

动作：

| 项 | 内容 |
| --- | --- |
| 原生分派 | `MainActivity.kt` 加 `openVideo` 方法，走 `openWithSystemPlayer()` |
| URI | `FileProvider.getUriForFile` 生成 `content://`，带 `FLAG_GRANT_READ_URI_PERMISSION` |
| 共享目录 | 新建 `android/app/src/main/res/xml/file_paths.xml`，列 external / external-files / files / cache |
| 包可见性 | manifest 的 `queries` 加两条 `ACTION_VIEW`：`video/*` 与 `application/x-mpegurl` |
| Dart 侧 | `VideoLauncher` 认 Android，`open()` 走通道 `mediashelf/playback` 的 `openVideo` |
| MIME | `VideoLauncher.mimeByExtension` 按扩展名给，认不出给 `video/*` |
| 授权前置 | `MediaBridge.ensureScanAccess()` 与 `ensureScanAccessOrPrompt()`，接上六个导入入口 |
| CI | 新建 `.github/workflows/ci.yml`，迁自 PictureViewer2 |
| 版本 | `pubspec.yaml` 升到 `1.0.0+17`，关于页常量同步 |

关键决定：

| 议题 | 决定与理由 |
| --- | --- |
| 通道复用 | 外链走已有的 `mediashelf/playback`，MainActivity 已经在处理这个通道，不新开 |
| 不用 file:// | Android 7 起 `file://` 会抛 `FileUriExposedException`，一律用 FileProvider |
| 先查有没有播放器 | `queryIntentActivities` 为空就直接返回 false，Dart 侧报 failed，界面提示比空跳转清楚 |
| 授权核对放界面层 | `AppState` 不 import `MediaBridge`（反向依赖会成环），所以核对做成共享助手，由各导入入口调用 |
| CI 固定版本 | 与本地一致，固定 Flutter 3.47.5。放开的只是 info，warning 与 error 仍然拦 |
| 版本收尾到 1.0.0 | 阶段 0 的记录写明阶段 9 收尾到 `1.0.0`，构建号顺延到 17 |

验证：

- `flutter analyze --no-fatal-infos`：5 条 info，0 error。
- `flutter test`：422 用例全过。新增 `test/widget/scan_access_snack_test.dart` 3 例与 `test/media_bridge_test.dart` 3 例、`test/services/video_launcher_test.dart` 4 例。
- `flutter build apk --release`：退出码 0。aapt2 核对清单：`versionName 1.0.0`、`versionCode 17`、authority `com.mediashelf.mediashelf.fileprovider`、queries 里两条 VIEW。
- CI 的 YAML 能解析，步骤与本地跑过的命令一致。

未完成事项：本机 `adb devices` 为空。阶段 9 的通过标准「实机能扫描一个目录，能拉起外部播放器」只能在设备上核对。CI 也没有远端运行记录（本机没装 gh，Actions 要等推送后才有结果）。

踩坑：`edit` 工具连续两次把相邻两行合成一行（删掉了尾随换行）。改 Kotlin 与 Dart 的长方法时改用 Python 脚本替换并断言出现次数。

## 2026-09-28 标签管理与多选批量操作（`1.1.0+18`）

用户报四个缺陷：「没有删除标签功能」「没有多选功能（打标签、删除等操作）」「左下角标签库一大块都是扩展名标签很难看，加入从命名空间折叠的功能并持久化」「添加新标签时命名空间栏根据已有的命名空间猜测，添加一样的标签时提醒」。

动作：

| 项 | 内容 |
| --- | --- |
| 命名空间折叠 | `AppState` 加 `collapsedNamespaces` / `isNamespaceCollapsed` / `toggleNamespaceCollapsed` / `setAllNamespacesCollapsed`，默认折叠 `ext`（几十个扩展名一次收起来），落盘进 `settings.json` 的 `collapsed_namespaces` |
| 折叠界面 | 标签面板命名空间标题改成可点，带箭头与「还有筛选生效」的小标记；表头加展开全部 / 折叠全部两个按钮，折叠后条目不再构建 |
| 规则标签保护 | `AppState.isRuleTag` 判定 `kind` / `ext` 命名空间：菜单里只给「折叠此命名空间」加一行说明，不给改名、改色、删除（规则标签删了也会在下次启动被 `ensureRuleTags` 补回来） |
| 删除标签 | `TagDao.countUsage(tagId)` 先数出会解除多少媒体与文件夹关联，确认框写清「将解除 N 个媒体、M 个文件夹的关联 / 磁盘上的文件不会被删除」，再由已有的 `deleteTag` 级联清 `media_tags` 与 `folder_tags` |
| 新建标签联想 | 对话框读 `AppState.knownNamespaces`（过滤掉 `general` / `kind` / `ext`）给命名空间建议 chip；同名同命名空间红字提醒并禁用创建，同名不同命名空间只提醒 |
| 视觉库多选 | 磁贴长按进多选（`_handleImageTap` 里多选模式下的单击改成勾选，不再打开查看器），选择条加全选与「从软件移除记录」（确认后走 `MediaDao.deleteByIds`，磁盘不动） |
| 曲目多选 | 曲目工具栏加多选开关，选中集非空时出现全选、批量加标签、批量移除标签、移除记录 |
| 旧对话框去重 | `lib/widgets/dialogs.dart` 里那份旧的 `showTagPickerDialog` 缺 `filterTagIds`，与 `tag_picker_dialog.dart` 的新版重名；`folder_browser.dart` 改成 `import 'dialogs.dart' hide showTagPickerDialog;` |
| 版本 | `pubspec.yaml` 升到 `1.1.0+18`，关于页常量同步 |

关键决定：

| 议题 | 决定与理由 |
| --- | --- |
| 折叠状态存哪 | 存 `settings.json` 而不是数据库：它是纯界面偏好，跟着 `not_tag_ids` 那套设置一起走，不必为它加表 |
| 默认折叠哪个 | 只默认折叠 `ext`：用户嫌的就是这一块；`kind` 只有四个，留着当筛选入口 |
| 规则标签为什么不能删 | `AppState.init()` 每次都跑 `ensureRuleTags`，删了下次启动会回来，给了删除按钮只会让人以为没生效。所以给折叠，不给删 |
| 移除记录而不是删除文件 | 与前面几轮的删除口径一致：软件里移除记录，磁盘文件不动，文案里写明 |
| 可见项登记 | 作品层的媒体行由 `ImageGrid` 自己查（`AppState.images` 在作品层是空的），所以 `ImageGrid` 每次重建后把可见媒体 id 登记回 `AppState`，全选与 Shift 区间选都按这份登记来 |
| 媒体代数 | 加 `AppState.mediaRevision`，删除后自增；作品层网格靠它知道要重查，不然磁贴会留在界面上 |

验证：

- `flutter analyze --no-fatal-infos`：5 条 info，0 error。
- `flutter test`：436 用例全过。新增 `test/state/app_state_tag_admin_test.dart` 7 例、`test/widget/tag_panel_test.dart` 6 例，并在 `test/widget/home_page_test.dart` 补「图片库多选：长按进多选，全选后批量移除记录」。
- `bash scripts/build_linux.sh --mode release`：退出码 0，产物 `build/linux/x64/release/bundle/mediashelf`，系统 sqlite3 已复制进 bundle 的 lib 目录。
- 界面层靠 widget 测试核对：折叠 / 展开全部、命名空间联想、同名提醒、规则标签菜单、删除确认文案、长按进多选、多选下单击不打开查看器、全选、批量移除后磁贴消失且磁盘文件还在。

未完成事项：Windows 与 Android 上没有跑过这一轮界面（本机只有 Linux 桌面与单元 / widget 测试）。

踩坑：

- `tag_panel.dart` 的表头在 260 宽的左栏里被新加的两个按钮挤爆（`RenderFlex overflowed by 21 pixels`）。把五个按钮统一压成 28 宽、外面再套一层右对齐的 `FittedBox(scaleDown)`，窄栏里整体缩一点，绝不溢出。
- widget 测试里的真实数据库 I/O 必须放在 `setUp`：写进测试体会卡到 10 分钟超时。
- 标签面板按命名空间字母序排，`ext` 一展开几十条会把后面的组挤出视野，`SliverList` 懒构建就找不到后面的条目。断言只看最前面那一组，或改用 `kind` 命名空间的标签。
- 「全选」最初写的是 `_images`。作品层这个列表是空的，点一下全选会把已选清空 —— 是测试逮出来的真 bug，不是测试写错。


## 2026-09-28 标签对话框折叠、左栏固定表头与图片/视频库标签栏（`1.2.0+19`）

用户报四个缺陷：「在给作品编辑标签的时候也要加上这个以命名空间收起/展开的效果」「左侧标签栏上下滚动浏览的时候上面筛选、添加等功能栏不能随着移动」「图片/视频居然没有标签栏」「浅色主题只对音频做了适配，其他两个选中后还是黑色显得非常难看」。

动作：

| 项 | 内容 |
| --- | --- |
| 标签选择对话框 | `lib/widgets/tag_picker_dialog.dart` 整文件重写：按命名空间分组，标题 `ValueKey('picker-ns-header-$key')` 可点收起/展开（空命名空间用空串做键，与 `AppState` 一致），行 `ValueKey('picker-tag-$id')`，底部「已选 N」，颜色全走 `AppColors.*Of(context)` |
| 左栏固定表头 | `lib/widgets/tag_panel.dart` 的 `_tagSection` 改成 `LayoutBuilder`：`maxHeight >= 170` 时用 `Column[_tagHeader, Divider, _tagSearchBar, if(activeIds.isNotEmpty) _activeFilterBar, Expanded(ListView.builder)]`，只让标签列表滚；矮于此退回原来的 `CustomScrollView`（整体一起滚） |
| 图片/视频库标签栏 | `lib/pages/home_page.dart` 加 `Map<String, String> _leftTabs`；`_buildLeftPanel({onNavigate})` 视觉库返回 `Column[_leftPanelTabs(tab, onNavigate), Divider, Expanded(tab == 'tags' ? TagPanel(filterOnly: true, onNavigate:) : FolderPanel(library: _library))]`，页签 key 为 `'$_library-left-tab-folders'` / `-tags`；抽屉版本同样走 `_buildLeftPanel(onNavigate: () => Navigator.of(drawerCtx).pop())` |
| 浅色主题适配 | 把 `lib/widgets/image_grid.dart`(15)、`lib/widgets/folder_panel.dart`(29)、`lib/widgets/works_grid.dart`(1)、`lib/widgets/image_detail.dart`(36)、`lib/widgets/tag_panel.dart`(3)、`lib/pages/home_page.dart`(5) 里的 `AppColors.<色名>` 换成 `AppColors.<色名>Of(context)`；`lib/widgets/image_viewer.dart` 的 19 处不动，全屏查看器保持深色底 |
| 主题访问器补齐 | `lib/theme/app_theme.dart` 加浅色常量 `textTertiaryLight #5A6070`、`mutedLighterC #9AA0B2`、`deepLight #E2E4EC`、`surfaceHighLight #B8BDCB` 与访问器 `textTertiaryOf` / `mutedLighterOf` / `deepOf` / `surfaceHighOf` |
| 版本 | `pubspec.yaml` 升到 `1.2.0+19`，关于页常量同步 |

关键决定：

| 议题 | 决定与理由 |
| --- | --- |
| 折叠状态共用一份 | 对话框与左栏都读 `AppState.collapsedNamespaces`：在哪儿收起来的，换个入口打开还是收着的，不必维护两套状态 |
| 搜索时忽略折叠 | 搜到的标签必须看得见，否则「搜不出来」会被当成「没有这个标签」；此时标题也不响应点击 |
| 固定行还是整体滚 | 矮窗口里（800x600 的音频左栏只剩 86 高）固定行会把面板顶出溢出条，所以按高度二选一，宁可退回整体滚也不溢出 |
| 视觉库给标签栏的方式 | 图片/视频库左栏原本只有文件夹树，直接换成标签面板会丢入口，所以做两个页签，各库记住各库的选择 |
| 查看器不跟着换色 | 全屏看图时深色底是刻意的（衬图片），只把网格、列表、详情、对话框这些界面改成随主题走 |

验证：

- `flutter analyze --no-fatal-infos`：5 条 info，0 error（`import_service.dart:45-47` 的 `prefer_initializing_formals` 与 `cover_image.dart:34` 的 `unnecessary_underscores`，都是既有项）。
- `flutter test`：444 用例全过。新增 `test/widget/tag_picker_dialog_test.dart` 4 例；`test/widget/tag_panel_test.dart` 补「滚动标签列表时表头与搜索框不跟着移动」「面板被压到几十像素高时退回整体滚动，不溢出」；`test/widget/image_grid_test.dart` 补「卡片底色跟着主题走」；`test/widget/home_page_test.dart` 补「图片库左栏：文件夹 / 标签两个页签可切换」。
- `bash scripts/build_linux.sh --mode release`：退出码 0，产物 `build/linux/x64/release/bundle/mediashelf`。
- 界面层核对：对话框分组收起/展开、搜索忽略折叠、已选计数与确定返回、浅色下对话框底色是 `panelLight`；左栏列表滚 600 时表头与搜索框坐标不变、列表内容上移；矮窗口退回整体滚且不抛异常；图片/视频库页签切换与各库记忆；浅色下网格卡片底色是 `surfaceLight`，深色下仍是 `surface`。

未完成事项：Windows 与 Android 上没有跑过这一轮界面（本机只有 Linux 桌面与单元 / widget 测试）。

踩坑：

- 批量把颜色换成 `...Of(context)` 后 54 处 `const` 失效（`const_eval_method_invocation`），写了一段脚本按 analyze 报的行列删掉最近的前一个 `const` 才回到基线。
- 左栏固定表头第一版直接上 `Column`：800x600 窗口下音频左栏只剩 86 高，`RenderFlex overflowed by 23 pixels on the bottom`，8 个既有用例一起红。加 `LayoutBuilder` 高度兜底后恢复。
- `AppState.createTag` 会把空命名空间归成 `general`，测试里要造真正的「无命名空间」标签得直接 `TagDao.insert(Tag(namespace: ''))` 再 `app.loadTags()`。
- `ListView.builder` 的 `maxScrollExtent` 是估出来的：`jumpTo` 到估出来的最大值会被重新算出的范围夹回去（实测 6285 被夹到 2051），测试改用 `jumpTo(600)` 这种确定值。
- 懒构建滚动后不一定回收已构建的分组，别拿「某个 key 还在不在」当「有没有滚」的证据，要拿坐标或 `position.pixels`。

## 2026-09-28 看图模式：滑动漂移、系统栏遮挡、缩略图不生成与视觉库排序（`1.3.0+20`）

用户报：「安卓端看图模式有严重问题，图片会随着滑动而移动导致根本无法操作和观看，上方 UI 顶着屏幕最顶端也点不到。对于图片模式来说，扫描进入的时候没有缩略图生成，图片详情也没用，也没有做到承诺的前置补零，图片和视频的排序也不知道在哪里。」

动作：

| 项 | 内容 |
| --- | --- |
| 缩略图服务启动 | `lib/state/app_state.dart` 的 `init()` 开头补 `await ThumbnailService.instance.init();`。此前 `ThumbnailService.instance.init()` 在整个 `lib/` 里一次都没被调用（只有 3 个测试调过），而 `lib/services/thumbnail_cache.dart` 用的是 `late String _cacheDir`，`thumbPath()` 一读就抛 `LateInitializationError` |
| 缩略图服务容错 | `lib/services/thumbnail_cache.dart` 把 `_cacheDir` 改成可空 `String? _cacheDir` 加 `_initialized` 标志，`cacheDir` 走 `_requireDir()`（未初始化给 `StateError('ThumbnailService 未初始化：先 await ThumbnailService.instance.init()')`），`init({String? cacheDir})` 幂等（不传目录时重复调用直接返回，传了目录总是重设，保住测试各自的临时目录），另加 `resetForTest()` |
| 网格不吞异常 | `lib/widgets/image_grid.dart` 的 `_checkAndGenerate` 把 `File? thumbFile;` 提到 `try` 外、`thumbPath` 调用挪进 `try`：缓存目录没准备好时只该落成「没有缩略图」，不该让异常从 post-frame 的 Future 里逃出去（那样 `_thumbFile` 永远是 null，网格只剩占位图） |
| 查看器不再被拖走 | `lib/widgets/image_viewer.dart` 的 `InteractiveViewer` 把 `boundaryMargin` 从 `EdgeInsets.all(double.infinity)` 改成 `EdgeInsets.zero`、`minScale` 从 0.05 提到 1.0、`maxScale` 从 50 收到 20；新增 `_dragDx` 累计手势横向位移（`onInteractionStart` 清零、`onInteractionUpdate` 里 `details.pointerCount <= 1` 时累加）；`_onInteractionEnd` 改成「松手速度 ≥200 或拖够屏宽 18%」都翻页；`_applyScale` 缩到 1 倍时直接 `Matrix4.identity()` 归位 |
| 系统栏留白 | 同文件的 `_buildTopBar` / `_buildBottomBar` / `_buildExifPanel` 全部读 `MediaQuery.viewPaddingOf(context)`：顶栏高 `52 + topInset`、底栏 `52 + bottomInset`、EXIF 面板 `top: 64 + top`，渐变仍铺到屏幕边 |
| sort_key 回填 | `lib/db/database.dart` 的 `init()` 在 `PRAGMA journal_mode=WAL` 之后调 `_backfillSortKeys(db)`：查 `sort_key IS NULL OR sort_key = ''` 的行，逐行用 `sortKeyOfPath(path)` 写回（`batch` 提交）。`sort_key` 是 v7 用 `ALTER TABLE` 加的，而迁移表是纯 SQL 列表、没有 Dart 侧钩子，老库全是 NULL，自然序因此退化成文件名字符串序 |
| 作品层排序 | `lib/widgets/image_grid.dart` 的 `_loadWorkItems` 原来自己 `..sort((a, b) => a.filename.compareTo(b.filename))`，把库里的自然序覆盖掉了；改成由外部传入 `int Function(MediaItem, MediaItem) sort`，调用处用 `appState.visualSortComparator` |
| 视觉库排序 | `lib/state/app_state.dart` 加图片 / 视频两套排序状态（`_imageSortKey` / `_imageSortDesc` / `_videoSortKey` / `_videoSortDesc`，键 `name` / `mtime` / `size` / `added`，`visualSortLabels` 给中文名），`visualSortComparator` 按当前库取一套、非文件名排序相等时回落 `MediaDao.compareNatural`、降序取负；`lib/services/settings_service.dart` 落 `image_sort_key` / `image_sort_desc` / `video_sort_key` / `video_sort_desc`；`lib/pages/home_page.dart` 的 `_VisualToolbar` 在视图模式按钮后加 `PopupMenuButton`（key `'$library-toolbar-sort'`，tooltip「排序」） |
| 图片详情跟页 | `AppState` 加 `_syncSelectedToViewer()`（把 `_viewerImages[_viewerIndex].id` 写进 `_selectedImageId`），`openViewer` / `navigateViewer` 都调用：翻大图时详情面板跟着走 |

关键决定：

| 议题 | 决定与理由 |
| --- | --- |
| 缩略图服务在哪初始化 | 放 `AppState.init()` 的日志行之后。`lib/main.dart` 的启动序列没有它，而界面一建卡片就会调 `thumbPath()`，放在服务层上游最省事；同时把「没初始化就读目录」从 `LateInitializationError` 换成能读懂的错误 |
| 缩略图目录可空还是兜底 | 不用临时目录兜底：兜底会把缩略图写进一个下次启动就找不到的地方，静静地白写一堆文件；宁可明确报错、并让网格降级成占位图 |
| 查看器边界 | 零边界：适应窗口时图与视口同大，无限边界会让任何一次滑动把画面拖出视口并停在那里（用户看到的「图片随着滑动而移动」）；零边界下适应窗口拖不动，放大后仍能在图内平移 |
| 缩到最小是否归位 | 归位。按焦点缩放会留下平移量，而零边界下适应窗口时拖不动，留着偏移就再也摆不正 |
| 翻页触发条件 | 速度与距离取或：只看松手速度的话，慢慢拖到底什么都不发生；距离阈值取屏宽 18%，避免误触 |
| 老库怎么补零 | 在 `DatabaseManager.init()` 打完 WAL 后跑一次 Dart 回填，而不是加一条迁移。`Tables.migrations` 是纯 SQL 列表，回填要读路径算 `sortKeyOfPath`，SQL 写不出来；回填只碰 `sort_key` 为空的行，重复启动是空操作 |
| 视觉库排序状态放哪 | 放 `AppState`（按库一套），不放各个界面：工具栏、网格、作品层排序都要读同一份，设置还要持久化 |
| 降序怎么实现 | 比较器里对结果取负，相等时仍先按自然序回落再取负，保证同值里的相对顺序稳定 |

验证：

- `flutter analyze --no-fatal-infos`：5 条 info，0 error（都是既有项：`import_service.dart:45-47` 的 `prefer_initializing_formals`、`cover_image.dart:34` 的 `unnecessary_underscores`）。
- `flutter test`：454 用例全过（上一版基线 444）。新增 10 例：`test/services/thumbnail_cache_test.dart` 2 例（未初始化给 `StateError`、不传目录的 `init` 幂等）；`test/db_migration_test.dart` 1 例（`DatabaseManager.init` 给老行回填 `sort_key`，`第10话.jpg` 的键是 `第0010话.jpg`、查询顺序 1/2/10，并验幂等）；`test/state/app_state_images_test.dart` 3 例（默认自然序与四种排序字段、降序；`AppState.init()` 真的初始化了缩略图服务；查看器翻页时 `_selectedImageId` 跟着走）；`test/widget/image_viewer_test.dart` 2 例（慢慢拖够距离也翻页且画面没被拖走、顶栏让开状态栏 / 底栏让开导航条）；`test/widget/home_page_test.dart` 2 例（排序菜单选反序后网格顺序真的变、窄窗口下工具栏不再 `RenderFlex` 溢出）。
- 界面层核对：查看器滑动后的变换矩阵回到单位阵、EXIF 面板跟着顶栏下移；图片库与视频库的排序各记各的，切库回来不串。
- `git diff --numstat` 与 `git diff -w --numstat` 每个文件都相等（12 个文件、643 加 / 34 减），确认改动里没有混进空白噪音。

未完成事项：Windows 与 Android 上没有跑过这一轮界面（本机没有安卓设备，只有 Linux 桌面与单元 / widget 测试）；查看器的滑动只在 widget 测试里模拟指针，真机手感仍需人确认。

踩坑：

- `ThumbnailService.instance.init()` 从没被调用，症状却是「扫描进去没有缩略图」：`late` 字段的 `LateInitializationError` 从 post-frame 的 Future 里逃出去不会红屏，只是那张卡片永远没有缩略图，所以查了半天界面层。教训：先 grep 一遍「某个单例的 init 到底有没有人调」。
- 同类问题一起受损：图片详情预览（`image_detail.dart` 的 `ensureThumbnail`）与设置页的缓存占用 / 清理（`home_page.dart`、`settings_page.dart`）都读同一个目录，服务没初始化时它们也全是坏的。
- `InteractiveViewer` 给了无限边界后，第 1 张到第 20 张「翻页」的手势其实全被它吃成平移；把边界收掉之前，翻页逻辑怎么写都测不出效果。
- widget 测试里的 `tester.takeException()` 只给一句摘要，拿不到出错的是哪个 widget；把 `FlutterError.onError` 临时换成 `FlutterError.dumpErrorToConsole` 才打出 `The relevant error-causing widget was: Row ... home_page.dart:387:18`，顺着 creator 链才确定是工具栏自己溢出（440 宽溢出 37 像素）。修法是紧凑阈值从 430 提到 500。
- 用 `MediaItem.toMap()` 直接插库时枚举要给 `.value`（`'media_type': MediaType.image.value`），给枚举本身会被 sqflite 拒掉。
- 本机 `dart format`（Dart 3.13.4 / Flutter 3.47.5）已换成 tall 样式，跑一次 `dart format lib test` 会重排 108 个文件、6213 加 / 3144 减，看着像把整个仓库改了一遍；HEAD 是旧 short 样式，在新工具链下复现不出来（`--language-version` 与 `--trailing-commas` 都试过）。清理办法：`git checkout` 回 HEAD，再只重放这一轮的功能改动，最后用「去掉空白与逗号后比较」的规范化脚本验证一条功能都没漏；判定「没有空白噪音」的硬指标是每个文件 `git diff --numstat` 等于 `git diff -w --numstat`。
- 用脚本批量替换 `_cacheDir` 时把 `_requireDir()` 自己的函数体也改成了 `_requireDir()`（无限递归）；批量替换必须先断言命中次数，不满足就整文件不落盘。

## 2026-09-28 九项缺陷与需求：窄栏适配、标签增删、封面选图、批量导入与缩略图补齐（`1.4.0+21`）

用户报九项（按条转述，原话见当轮对话）：①P2 工具栏溢出要修，P1 先放。②手机端上方多选栏超出长度，适配很差。③看图模式的选项栏左右余量不足，曲面侧边屏点不到关闭。④三个竖点里没有删除标签的选项，文件夹标签删不掉，也无法递归删子标签。⑤图片详情还是打不开（空白或占位）。⑥电脑端图片第一次导入没有缩略图，重启才有。⑦手机端选封面要直接从这个文件夹的图片里选。⑧支持批量导入文件夹，每个文件夹按作品导入。⑨图片与视频无法快捷回到「作品」显示方式。

用户口径：④ 左栏文件夹与中间磁贴同样处理，并为「作品」层级也加标签增删；⑨ 工具栏或面包屑加一个「作品」按钮；⑤ 页面打得开，但里面是空白或只有占位。

动作：

| 项 | 内容 |
| --- | --- |
| ① 工具栏溢出 | `lib/pages/home_page.dart:393` 起，`_VisualToolbar` 新增 `tiny = maxWidth < 220`（宽版布局加详情面板时中间列只有 138），图标按钮收到 30 见方、图标 16 见方；排序按钮包进 `if (!tiny)`，`tiny` 时排序项挪进「更多」菜单（值 `sort:<key>` 与 `sortDir`，见 :554 与 :638） |
| ② 多选栏 | 同文件 `_SelectionBar`（:806）改用 `LayoutBuilder`：`narrow = maxWidth < 520` 时动作改图标按钮并留提示气泡，`tight = maxWidth < 300` 时收到 30 见方、标签只留「N 项」，动作区套一层横向滚动。键值不变 |
| ③ 查看器安全区 | `lib/widgets/image_viewer.dart:885` 与 :1073 的顶栏与底栏除上下内边距外，再让开 `viewPadding.left` 与 `.right`：曲面侧边屏上「关闭」与翻页按钮不贴边 |
| ④ 标签增删 | 文件夹 ⋮ 菜单加「移除标签...」（`lib/widgets/folder_browser.dart:381`，处理在 :429，走 `_confirmSync` 询问是否递归到子文件夹）；磁贴 ⋮ 菜单加「添加标签...」与「移除标签...」（`lib/widgets/image_grid.dart:91` 的 `_editMediaTags`，移除时先取这条媒体已有的标签收窄候选）；作品卡片菜单加同一对（`lib/widgets/works_grid.dart:227` 起，一次作用于整个作品） |
| ⑤ 图片详情空白 | `lib/state/app_state.dart:102` 把 `reportVisibleMediaIds(List<int>)` 换成 `reportVisibleMedia(List<MediaItem>)`，媒体行并进 `_imageIndex`；新增 `ensureDetailSelection()`（:639）在打开详情前兜底选中查看器当前图或列表第一张，一张都没有就提示先导入。它只写 `_selectedImageId` 与 `_anchorImageId`，不动多选集合 |
| ⑥ 缩略图补齐 | `AppState.backfillThumbnails`（`lib/state/app_state.dart:1561`）后台逐张补 300 像素缩略图，每补 8 张 `thumbEpoch` 加一；导入结束把新路径丢进队列（:1545）；`lib/widgets/image_grid.dart:207` 每次进入新的库 / 文件夹 / 作品上下文也补一次。口径见第 7.6 节 |
| ⑦ 封面选图 | 新增 `lib/widgets/cover_pick.dart`（图墙与 `showCoverImagePicker`，:95）。作品封面先列作品里的图片（`lib/widgets/dialogs.dart:65`），卷封面先列本文件夹（含子文件夹）的图片（`lib/widgets/volume_cover_dialog.dart:106`），系统选图留作出口 |
| ⑧ 批量导入 | `AppState.importSubdirectoriesAsWorks`（`lib/state/app_state.dart:1911`）把含该库媒体的直接子目录各建一个作品，子目录都没有时退回单目录导入；入口在左栏（`lib/widgets/folder_panel.dart:469`）与作品层空状态（`lib/widgets/works_grid.dart:132`） |
| ⑨ 回作品层 | 面包屑加「作品」按钮（`lib/pages/home_page.dart:696`，调 `goHome()`）；`_BreadcrumbBar` 的显示条件从「有当前文件夹」改成 `breadcrumb.isNotEmpty`（:215）；删掉原来循环 `goUp` 的 `_goRoot` |

关键决定：

| 议题 | 决定与理由 |
| --- | --- |
| 图墙还是系统选图 | 先图墙。手机上系统选图要一层层点目录，而封面图本来就在库里，列出来最快；系统选图留作「都不合适」的出口 |
| 兜底选中要不要动多选集合 | 不动。详情面板只读 `selectedImage`，多选集合是用户的框选结果；旧的 `selectImage()` 会把框选清掉，一开详情就丢选择 |
| 批量导入怎么算一个作品 | 一个直接子目录算一个作品，名字取目录名。音频库不适用（那边一个目录是一家，子目录是卷），调用时直接拒绝并记日志 |
| 标签移除要不要先收窄候选 | 要。否则用户能从全库标签里挑一个根本不在这张图上的标签来「移除」，操作完没有任何反馈 |
| 小磁贴的 ⋮ 多大 | 26 见方。Material 3 默认 48 见方，手机上磁贴只有 80 到 90 像素，⋮ 会盖住整张磁贴并吃掉单击与长按 |
| 窄窗用滚动还是继续缩 | 先缩到 30 见方，再套横向滚动兜底。两者都做才能在 218 宽下不溢出，用户仍能摸到全部动作 |

验证：

- `flutter analyze --no-fatal-infos`：5 条 info，0 error（都是既有项：`import_service.dart:45-47` 的 `prefer_initializing_formals`、`cover_image.dart:34` 的 `unnecessary_underscores`）。
- `flutter test`：462 用例全过（上一版基线 454）。新增 8 例：`test/state/app_state_images_test.dart` 3 例（『作品层的可见媒体要登记进索引，详情才有兜底的选中项』、『批量导入：每个含媒体的子文件夹各建一个作品』、『导入后后台补齐缩略图，并让已建的占位卡片重新检查』）；`test/widget/home_page_test.dart` 5 例（『视觉库工具栏：窄窗口 + 打开详情面板也不溢出（回归：800 宽溢出 30 像素）』、『极窄工具栏：连排序也收进「更多」菜单（详情面板占剩的 218 宽）』、『手机宽度下的多选栏改成图标按钮，不再溢出』、『作品层一键回「作品」：面包屑上的作品按钮』、『作品卡片菜单能添加/移除标签（作用于整个作品）』）。
- 界面层核对：多选栏 5 个键值未变，桌面端文字按钮照旧；`viewPadding` 为 0 时查看器顶栏与底栏尺寸不变；批量导入第二次调用返回 0。
- `git diff --numstat`：11 个文件、1318 加 / 190 减，没有混进空白噪音（清理过程见踩坑）。

未完成事项：Windows 与 Android 上没有跑过这一轮界面（本机只有 Linux 桌面与单元 / widget 测试）；批量导入只在测试里验证，真机选目录与扫大目录的耗时未测；真机曲面屏的安全区留白只按 `viewPadding` 推算。

踩坑（格式与工具）：

- `dart format lib test` 一次重排 108 个文件。第一次分类错了：把 HEAD 版本拷到包外 `/tmp` 再格式化，语言版本与包内不同（`pubspec.yaml:33` 是 `sdk: ^3.12.2`），把纯格式文件误判成有改动。正确办法是把 HEAD 版本拷进仓库内的临时目录再格式化、`cmp`。结果 24 个纯格式文件回退，只剩 11 个真改动。
- 本机 Dart 3.13 只出 tall 样式，`--language-version=3.6` 被忽略，旧 short 样式复现不出来。清理用三方合并：`git merge-file -p --theirs <HEAD 版本> <format(HEAD 版本)> <工作区>`，再用「去空白加去尾逗号」的规范化脚本逐文件比对，11 个全部一致。

踩坑（定位与测试）：

- 218 宽那 20 像素溢出不在工具栏，而在多选栏；多选栏出现的原因又是打开详情时的兜底选中往 `_selectedImageIds` 里塞了一项。用 `FlutterError.onError` 打印 `debugCreator` 才看出是 `_SelectionBar`。
- widget 测试里 380 宽长按磁贴不进多选，最后查到是小磁贴上 ⋮ 的 48 见方触摸区盖住了 `getCenter` 那个点。
- `find.text('修改时间')` 在窄屏详情里同时命中菜单项与详情信息，改用 `find.ancestor(of: find.text(...), matching: find.byType(CheckedPopupMenuItem<String>))`；`CheckedPopupMenuItem` 必须带类型参数，`byType` 比对运行时类型。
- 用 200 宽窗口测 `tiny` 时，点「更多」的偏移打不到按钮，命中链顶端是关着的 Drawer 边缘拖拽层。改用 800 宽加详情面板制造 `tiny`。
- 改 `pubspec.yaml` 的版本号时漏了 `lib/pages/about_page.dart` 的 `appVersion` 常量。全量测试在版本号改之前跑过，所以是提交后才发现的（`test/widget/settings_page_test.dart` 的「关于页写死的版本号与 pubspec.yaml 同步」把它拦住）。教训：版本号属于最后一步，改完要重跑全量测试再提交。

## 2026-09-29 只读代码质量审查与缺陷修复（P1 全清，P2 批次 A）

目标：先对 `1.4.0+21`（当时 HEAD `dd15076`）做只读代码质量审查，出有源码依据的报告；经用户确认后按报告逐条验证与修复。

审查：

| 项 | 内容 |
| --- | --- |
| 范围 | `lib/` 67 个文件 24101 行、`test/` 55 个文件 11434 行。通读加定向 grep，全程未改动文件 |
| 结论 | 无 P0；P1 九条；P2 三十八条，按性能、数据一致性、重复与死代码、无障碍与国际化、工程与文档分五组 |
| 报告 | 本次会话内的 `/tmp/mediashelf-review.md`（212 行，仓库外，不入库）。每条给出 file:line、后果、已排除的可能、未验证项 |
| 写法 | 每条先写能复现的红测试，再改代码，再摘掉修复复跑一次确认用例真的红 |

动作（已修的十八条）：

| 编号 | 缺陷 | 修复 |
| --- | --- | --- |
| P1-1 | `logError(..., data)` 的 data 参数从未使用 | `lib/utils/log_util.dart` 重写，data 进正文并作 `dev.log` 的 error |
| P1-4 | 从不写日志文件，界面却让用户去 logs 目录看 | 同上，`LogUtil.attachFileSink` 写 `logs/app-<日期>.log`，满 2MB 轮转 `.1` |
| P1-2 | 三处「先删目标再改名」有丢文件窗口 | 新增 `lib/utils/file_io.dart` 的 `writeFileAtomic`，cover、settings、data_dir 三处改用 |
| P2-8 | 批量删除分批各删各的，中途失败留下一半 | `lib/db/media_dao.dart` 的分批循环包进同一个事务 |
| P2-19 | `MigrationService` 开已有库不跑 onUpgrade，库被盖上 v8 的章而结构停在 v7 | 抽出 `Tables.createAll` 与 `Tables.applyMigrations`，两处调用点共用 |
| P1-7 | 深度删除不自增 `mediaRevision`，作品层磁贴残留 | `lib/state/app_state.dart` 的两处 prune 按删除条数自增 |
| P2-21 | 缩略图布尔守卫吞掉重生成 | 新增 `lib/utils/latest_only_runner.dart`，卡片复用时旧图结果不再盖回来 |
| P1-3 | 外链播放的成功是假成功 | `lib/services/video_launcher.dart` 给 Android 桥加超时；桌面路径读退出码，留 1.2 秒宽限期 |
| P2-13 | 数据目录迁移漏搬 `playlist/` | `lib/services/data_dir_service.dart` 补一条 `_copyDirStrict` |
| P1-6 | 迁移时两个库各自全读进内存逐字节比 | 改成 64KB 分块比较 |
| P1-8 | 缩略图补齐队列用 `contains` 加 `removeAt(0)`，是 O(n²) | 换成 Set 去重加 `removeLast` |
| P1-9 | 导入进度逐文件通知，整页重建 | 新增 `lib/utils/progress_throttle.dart`，按千分位整数每 1% 通知一次 |
| P1-5 | 界面与 README 承诺拖拽导入，代码里没有这个能力 | 按「不做该功能」处置，删两处文案、README 说法与 `desktop_drop` 依赖 |
| P2-14 | `p.basenameWithoutExtension` 只认当前平台分隔符 | 新增 `lib/services/media_rules.dart` 的 `stemOfPath`，字幕匹配与封面白名单改用 |
| P2-12 | 手动封面文件被删后仍直接返回，卡片一直空着 | `effectiveCover` 先查存在性，不在了落回自动候选 |
| P2-15 | 播放列表覆盖写与重名撞车 | 改原子写；只在替换真的改动了名字时补一段短哈希 |
| P2-16 | 覆盖目标库前先把目标库删掉，而备份只盖源库 | `migration_service.dart` 删之前先备份目标库，报告里给出备份目录 |
| P2-20 | 导入读文件大小或修改时间失败时静默按 0 入库 | 改 `logWarn`，带上路径与异常 |
| P2-17 | 阅读进度服务带一秒节流窗口，却从没人收尾 | 换库实例时收掉旧服务；关库前 `disposeReadingService` 先落盘；`dispose` 改成同步失效、异步落盘 |

验证：

- `flutter analyze`：5 条既有 info，0 error 0 warning（`lib/services/import_service.dart:45-47`、`lib/widgets/cover_image.dart:34`）。
- `flutter test`：505 用例全过（本轮起始基线 462）。
- 变异验证逐条做过。例：把 `lib/db/media_dao.dart` 的分批事务摘掉，回滚用例报 `Expected: <600> Actual: <100>`；把 `lib/state/app_state.dart` 的 `unawaited(stale.dispose())` 摘掉，新用例报 `database_closed`。
- 提交：`41da5a6` 迁移 onUpgrade、`fa6e340` 日志、`f3c74f4` 原子写与批量删除、`46d4b42` mediaRevision 与缩略图、`e67ca99` 外链播放与迁移流式、`39b4081` 拖拽文案、`91ea0fd` 路径分隔符、`79e116c` 批次 A。

未完成事项：报告里的 P2 还剩 22（`lib/widgets/dialogs.dart:187-325` 旧 `showTagPickerDialog` 死代码约 139 行，另有 `lib/widgets/works_grid.dart:10-12` 与 `lib/widgets/folder_browser.dart:11` 的化石 `hide`）、23（`lib/widgets/color_picker_dialog.dart` 无调用者，约 360 行）、24 到 27（三份 `_PromptDialog`、四份目录选择、`folder_browser` 两个批量方法、`image_grid` 的网格与列表分支重复）、28（32 份逐字节相同的 `_FakePathProvider`，可抽 `test/support/test_env.dart`）、30（`lib/utils/sql_like.dart` 的 `escapeLike` 与两个 DAO 各自手写的共三份）、31（`AppColors.parseColor` 遇到 8 位 `#RRGGBBAA` 会把红通道与 alpha 对调，与 `lib/utils/color_util.dart` 的 `parseHexColor` 两套语义）、32（`lib/widgets/segment_panel.dart:106`、`lib/widgets/tag_panel.dart:753/754/893/894`、`lib/widgets/image_detail.dart:785` 的 `TextEditingController` 无配对 dispose）、33（全 `lib` 零 `Semantics`，7 个纯图标按钮无 tooltip，`MaterialApp` 无 `localizationsDelegates`）、36（`lib/pages/about_page.dart:28` 版本号硬编码）。

踩坑：

- `lib/db/tables.dart` 的 `import` 要放在库级文档注释之上。夹在注释与 `class Tables` 之间会新增一条 `dangling_library_doc_comments`。
- `ProgressThrottle` 第一版用 double 比较步长，撞上 `0.21 - 0.2 = 0.00999…` 的浮点边界，改用千分位整数。
- `ReadingProgressService.dispose` 原本等 `flush()` 完成才置 `_disposed`。调用方是 fire-and-forget 时，紧接着的一次 `record` 会穿过 `_ensureUsable()` 打到已关闭的连接上。

下一步：继续修 P2 剩下的批次，先做「重复与死代码」与「无障碍与国际化」两组。
