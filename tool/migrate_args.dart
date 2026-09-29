/// `tool/migrate.dart` 与 `tool/migrate_check.dart` 共用的参数解析。
class MigrateArgs {
  MigrateArgs({
    required this.srcA,
    required this.srcB,
    required this.dst,
    this.backup = true,
    this.overwrite = false,
  });

  /// AudioShelf 老库（audioshelf.db）
  final String srcA;

  /// PictureViewer2 老库（pv2.db）
  final String srcB;

  /// 目标库（mediashelf.db）
  final String dst;

  /// 迁移前是否备份老库，默认备份。
  final bool backup;

  /// 目标库已有数据时是否覆盖，默认不覆盖。
  final bool overwrite;

  static const String usage =
      '用法：--src-a <AudioShelf 老库> --src-b <PictureViewer2 老库> --dst <新库> '
      '[--no-backup] [--overwrite]';

  /// 解析失败返回 null，调用方打印 [usage] 后退出。
  static MigrateArgs? parse(List<String> args) {
    String? srcA;
    String? srcB;
    String? dst;
    var backup = true;
    var overwrite = false;
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      String? take(String name) {
        if (arg == name) {
          if (i + 1 >= args.length) return null;
          i++;
          return args[i];
        }
        if (arg.startsWith('$name=')) return arg.substring(name.length + 1);
        return null;
      }

      final a = take('--src-a');
      if (a != null) {
        srcA = a;
        continue;
      }
      final b = take('--src-b');
      if (b != null) {
        srcB = b;
        continue;
      }
      final d = take('--dst');
      if (d != null) {
        dst = d;
        continue;
      }
      if (arg == '--no-backup') {
        backup = false;
        continue;
      }
      if (arg == '--overwrite') {
        overwrite = true;
        continue;
      }
      return null;
    }
    if (srcA == null || srcB == null || dst == null) return null;
    return MigrateArgs(
        srcA: srcA, srcB: srcB, dst: dst, backup: backup, overwrite: overwrite);
  }
}
