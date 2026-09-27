import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/log_util.dart';

/// 数据目录服务：统一管理数据库 / 封面缓存 / 设置文件的根目录。
///
/// 目录结构：
/// ```
/// <dataDir>/audioshelf.db
/// <dataDir>/covers/
/// <dataDir>/settings.json
/// ```
class DataDirService {
  DataDirService._();

  static final DataDirService instance = DataDirService._();

  static const String _dbFileName = 'audioshelf.db';

  String? _dataDir;

  Future<String> defaultDir() async {
    // 默认放在应用私有支持目录内（而非用户文档目录），各平台对应：
    // Windows %APPDATA%、Linux ~/.local/share、Android 应用私有目录。
    final docs = await getApplicationSupportDirectory();
    return p.join(docs.path, 'AudioShelf');
  }

  Future<String> _pointerFile() async {
    return p.join(await defaultDir(), '.datadir');
  }

  Future<String> get dataDir async {
    if (_dataDir != null) return _dataDir!;

    final def = await defaultDir();
    var result = def;
    try {
      final pf = await _pointerFile();
      final f = File(pf);
      if (f.existsSync()) {
        final content = f.readAsStringSync().trim();
        if (content.isNotEmpty) {
          result = content;
        }
      }
    } catch (e) {
      logWarn('DataDir', '读取指针文件失败: $e');
    }

    _dataDir = result;
    await Directory(result).create(recursive: true);
    return result;
  }

  Future<void> init() async {
    final dir = await dataDir;
    logInfo('DataDir', 'Data dir: $dir');
  }

  /// 清掉缓存的目录，让下一次访问重新读指针文件。仅供测试。
  @visibleForTesting
  void resetCache() {
    _dataDir = null;
  }

  /// 把数据目录整体搬到 [newDir]。
  ///
  /// 顺序：先复制并逐个校验，最后才写指针。任何一步失败都抛异常，且不碰指针，
  /// 旧目录仍是当前数据目录，应用保持在可用状态。
  Future<String> migrateTo(String newDir) async {
    final oldDir = p.normalize(await dataDir);
    final newD = p.normalize(newDir);

    if (p.equals(oldDir, newD)) {
      logInfo('DataDir', '目标目录即当前目录，无需迁移: $newD');
      return newD;
    }

    await Directory(newD).create(recursive: true);

    final oldDb = p.join(oldDir, _dbFileName);
    final newDb = p.join(newD, _dbFileName);
    await _copyFileStrict(oldDb, newDb);
    // WAL 里可能还有没 checkpoint 的页，少拷一份就可能丢最近写入。
    await _copyFileStrict('$oldDb-wal', '$newDb-wal');
    await _copyFileStrict(
        p.join(oldDir, 'settings.json'), p.join(newD, 'settings.json'));
    await _copyDirStrict(p.join(oldDir, 'covers'), p.join(newD, 'covers'));

    // 指针最后写，且先写临时文件再 rename，避免写一半留下坏指针。
    final def = await defaultDir();
    await Directory(def).create(recursive: true);
    final pointer = p.join(def, '.datadir');
    final tmp = File('$pointer.tmp');
    await tmp.writeAsString(newD, flush: true);
    if (File(pointer).existsSync()) {
      await File(pointer).delete();
    }
    await tmp.rename(pointer);

    _dataDir = newD;
    logInfo('DataDir', 'Migrated data dir: $oldDir -> $newD');
    return newD;
  }

  /// 复制文件并校验字节数。
  ///
  /// 目标已存在同名文件时：内容一致就跳过（迁移可重跑），内容不同就抛异常。
  /// 旧实现无条件覆盖，迁到已有数据的目录会用旧库盖掉新库。
  Future<void> _copyFileStrict(String src, String dst) async {
    final s = File(src);
    if (!s.existsSync()) return;

    final d = File(dst);
    if (d.existsSync()) {
      if (await _sameBytes(s, d)) {
        logInfo('DataDir', '目标已有一致文件，跳过: $dst');
        return;
      }
      throw StateError('目标目录已有不同内容的同名文件，拒绝覆盖: $dst');
    }

    await d.parent.create(recursive: true);
    await s.copy(dst);

    final srcLen = await s.length();
    final dstLen = await d.length();
    if (srcLen != dstLen) {
      try {
        await d.delete();
      } catch (_) {
        // 清理失败不影响结论，源文件仍在。
      }
      throw StateError('复制校验失败，字节数 $dstLen != $srcLen: $dst');
    }
  }

  Future<bool> _sameBytes(File a, File b) async {
    if (await a.length() != await b.length()) return false;
    final ab = await a.readAsBytes();
    final bb = await b.readAsBytes();
    for (int i = 0; i < ab.length; i++) {
      if (ab[i] != bb[i]) return false;
    }
    return true;
  }

  Future<void> _copyDirStrict(String src, String dst) async {
    final s = Directory(src);
    if (!s.existsSync()) return;
    await for (final entity in s.list(recursive: true)) {
      if (entity is File) {
        final rel = p.relative(entity.path, from: src);
        await _copyFileStrict(entity.path, p.join(dst, rel));
      }
    }
  }
}
