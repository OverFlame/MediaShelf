import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../utils/log_util.dart';
import 'data_dir_service.dart';

/// 持久化设置服务（JSON 文件，位于数据目录 settings.json）。
class SettingsService {
  SettingsService._();

  static final SettingsService instance = SettingsService._();

  Map<String, dynamic> _data = {};

  Future<File> _file() async {
    return File(p.join(await DataDirService.instance.dataDir, 'settings.json'));
  }

  Future<void> init() async {
    final f = await _file();
    _data = {};
    if (f.existsSync()) {
      try {
        _data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      } catch (e) {
        logWarn('Settings', '解析 settings.json 失败: $e');
        _data = {};
      }
    }
    logInfo('Settings', 'Initialized OK');
  }

  /// 保存串行链。两次保存交错时 writeAsString 的截断与写入会互相穿插，
  /// 留下半个 JSON；这里让保存排队，写文件本身也做成先写临时文件再改名。
  Future<void> _saveChain = Future<void>.value();

  Future<void> _save() {
    final next = _saveChain.then((_) => _writeSettingsFile());
    // 链尾只保留不会失败的 future：一次写失败不能卡住后面的保存。
    _saveChain = next.catchError((Object _) {});
    return next;
  }

  Future<void> _writeSettingsFile() async {
    final f = await _file();
    await f.parent.create(recursive: true);
    // 先写临时文件，再改名。读者要么看到完整旧内容，要么看到完整新内容。
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(_data), flush: true);
    if (f.existsSync()) {
      await f.delete();
    }
    await tmp.rename(f.path);
  }

  /// 清空内存状态并重置保存链，仅供测试。
  @visibleForTesting
  void resetForTest() {
    _data = {};
    _saveChain = Future<void>.value();
  }

  // ── 主题 ──
  ThemeMode get themeMode {
    final v = _data['theme_mode'] as String? ?? 'dark';
    return switch (v) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _data['theme_mode'] = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      _ => 'system',
    };
    await _save();
  }

  // ── 曲目排序 ──
  String get sortKey => (_data['sort_key'] as String?) ?? 'filename';

  Future<void> setSortKey(String key) async {
    _data['sort_key'] = key;
    await _save();
  }

  bool get sortDescending => (_data['sort_desc'] as bool?) ?? false;

  Future<void> setSortDescending(bool desc) async {
    _data['sort_desc'] = desc;
    await _save();
  }

  // ── 高级筛选表达式历史 ──
  List<String> get expressionHistory {
    final raw = _data['expr_history'];
    if (raw is List) return raw.whereType<String>().toList();
    return const [];
  }

  int get maxExprCacheCount => (_data['expr_cache_count'] as int?) ?? 10;

  Future<void> setMaxExprCacheCount(int count) async {
    _data['expr_cache_count'] = count.clamp(0, 100);
    await _save();
    final list = expressionHistory;
    final cap = _data['expr_cache_count'] as int;
    if (list.length > cap) {
      _data['expr_history'] = list.sublist(0, cap);
      await _save();
    }
  }

  Future<void> addExpression(String expression) async {
    final expr = expression.trim();
    if (expr.isEmpty) return;
    final list = expressionHistory.where((e) => e != expr).toList();
    list.insert(0, expr);
    final cap = maxExprCacheCount;
    _data['expr_history'] = cap <= 0 ? const <String>[] : list.take(cap).toList();
    await _save();
  }

  Future<void> clearExpressionHistory() async {
    _data['expr_history'] = const <String>[];
    await _save();
  }

  // ── 封面缓存上限（MB，0 表示不限制）──
  int get coverCacheLimitMB => (_data['cover_cache_mb'] as int?) ?? 512;

  Future<void> setCoverCacheLimitMB(int mb) async {
    _data['cover_cache_mb'] = mb.clamp(0, 8192);
    await _save();
  }
}
