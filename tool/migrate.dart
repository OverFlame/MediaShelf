import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:mediashelf/services/migration_service.dart';

import 'migrate_args.dart';

/// 把两个老库并进新库。
///
/// 例：dart run tool/migrate.dart \
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
  final service = MigrationService(
    factory: databaseFactoryFfi,
    backupOldDbs: parsed.backup,
    overwriteDst: parsed.overwrite,
    logger: (message) => stdout.writeln('[migrate] $message'),
  );

  try {
    final report = await service.run(
      srcAudioDb: parsed.srcA,
      srcImageDb: parsed.srcB,
      dstDb: parsed.dst,
    );
    stdout.writeln(report.summary);
    stdout.writeln('目标库：${report.dstDb}');
    stdout.writeln('备份目录：${report.backupDir ?? '(没有备份)'}');
    if (report.skippedTables.isNotEmpty) {
      stdout.writeln('跳过老表：${report.skippedTables.join('、')}');
    }
    if (report.duplicatePaths.isNotEmpty) {
      stdout.writeln('两边都有的 path（保留先到者）：${report.duplicatePaths.join('、')}');
    }
    stdout.writeln('迁移完成，接下来跑：dart run tool/migrate_check.dart '
        '--src-a "${report.srcAudioDb}" --src-b "${report.srcImageDb}" '
        '--dst "${report.dstDb}"');
    exit(0);
  } catch (error, stack) {
    stderr.writeln('迁移失败：$error');
    stderr.writeln(stack);
    exit(1);
  }
}
