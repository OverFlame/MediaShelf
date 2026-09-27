# Third-Party Notices

本项目使用以下第三方开源组件。各组件均采用宽松许可证（MIT / BSD / Apache / Zlib 等），
不包含 GPL/AGPL 等强 copyleft 依赖，可自由用于商业用途。

## 运行时依赖

| 组件 | 许可证 | 用途 |
| --- | --- | --- |
| [flutter_soloud](https://pub.dev/packages/flutter_soloud) | MIT | 音频播放引擎（内嵌 SoLoud，见下） |
| [audio_metadata_reader](https://pub.dev/packages/audio_metadata_reader) | MIT | 音频元数据 / 内嵌封面读取 |
| [provider](https://pub.dev/packages/provider) | MIT | 状态管理 |
| [sqflite](https://pub.dev/packages/sqflite) / sqflite_common_ffi | BSD-3-Clause | SQLite 数据库 |
| [file_picker](https://pub.dev/packages/file_picker) | MIT | 文件/文件夹选择 |
| [path_provider](https://pub.dev/packages/path_provider) | BSD-3-Clause | 数据目录 |
| [shared_preferences](https://pub.dev/packages/shared_preferences) | BSD-3-Clause | 设置持久化 |
| [path](https://pub.dev/packages/path) | BSD-3-Clause | 路径处理 |
| [cupertino_icons](https://pub.dev/packages/cupertino_icons) | MIT | 图标 |

## 内嵌组件（随 flutter_soloud 的 SoLoud 内核）

| 组件 | 许可证 |
| --- | --- |
| SoLoud | zlib/libpng |
| miniaudio | MIT / Public Domain |
| dr_libs (dr_mp3 / dr_wav / dr_flac) | MIT-0 / Public Domain |
| minimp3 | CC0 |
| pffft | BSD-3-Clause |
| stb_vorbis 等 | Public Domain / MIT |

以上内嵌组件均为宽松许可证，无需在二进制形式中署名
（详见 SoLoud 官方说明：https://soloud-audio.com/legal.html）。

完整依赖清单见 `pubspec.lock`，各包完整许可证文本见其发布页及本地 pub 缓存。
