import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:mediashelf/services/migration_check.dart';

import 'migrate_args.dart';

/// 迁移后的五项校验，全部通过退出码才是 0。
///
/// 例：dart run tool/migrate_check.dart \
///   --src-a "$HOME/.local/share/AudioShelf/audioshelf.db" \
///   --src-b "$HOME/PictureViewer/pv2.db" \
///   --dst "$HOME/.local/share/MediaShelf/mediashelf.db"
Future<void> main(List<String> args) async {
  final parsed = MigrateArgs.parse(args);
  if (parsed == null) {
    stderr.writeln('参数不完整');
    stderr.writeln(MigrateArgs.usage);
    exit(2);
  }

  sqfliteFfiInit();
  final checker = MigrationChecker(factory: databaseFactoryFfi);
  try {
    final report = await checker.run(
      srcAudioDb: parsed.srcA,
      srcImageDb: parsed.srcB,
      dstDb: parsed.dst,
    );
    stdout.writeln(report.summary);
    exit(report.passed ? 0 : 1);
  } catch (error, stack) {
    stderr.writeln('校验跑不起来：$error');
    stderr.writeln(stack);
    exit(1);
  }
}
