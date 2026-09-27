import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../db/database.dart';
import '../db/folder_dao.dart';
import '../db/tag_dao.dart';
import '../db/track_dao.dart';
import '../db/work_dao.dart';
import '../services/cover_service.dart';
import '../services/data_dir_service.dart';
import '../services/file_scanner.dart';
import '../services/import_service.dart';
import '../services/settings_service.dart';
import '../services/subtitle_parser.dart';
import '../utils/filter_expression.dart';
import '../utils/log_util.dart';
import 'player_controller.dart';

/// 标签筛选规则
class TagFilter {
  final List<int> andTagIds;
  final List<int> orTagIds;
  final List<int> notTagIds;

  const TagFilter({
    this.andTagIds = const [],
    this.orTagIds = const [],
    this.notTagIds = const [],
  });

  bool get active =>
      andTagIds.isNotEmpty || orTagIds.isNotEmpty || notTagIds.isNotEmpty;
}

/// 应用状态 — 作品集 / 文件夹导航 / 曲目 / 标签 / 导入 / 播放
class AppState extends ChangeNotifier {
  final PlayerController player;

  // ── 作品集 ──
  List<Work> _works = [];
  List<Work> get works => _works;
  Work? _currentWork;
  Work? get currentWork => _currentWork;
  List<VirtualFolder> _unassignedFolders = [];
  List<VirtualFolder> get unassignedFolders => _unassignedFolders;

  // ── 文件夹导航 ──
  int? _currentFolderId;
  int? get currentFolderId => _currentFolderId;
  VirtualFolder? _currentFolder;
  VirtualFolder? get currentFolder => _currentFolder;
  String? _currentFolderPath;
  String? get currentFolderPath => _currentFolderPath;
  List<VirtualFolder> _breadcrumb = [];
  List<VirtualFolder> get breadcrumb => _breadcrumb;
  int _folderVersion = 0;
  int get folderVersion => _folderVersion;

  // ── 中间栏内容 ──
  List<VirtualFolder> _centerFolders = [];
  List<VirtualFolder> get centerFolders => _centerFolders;
  List<TrackItem> _tracks = [];
  List<TrackItem> get tracks => _tracks;
  bool _loading = false;
  bool get loading => _loading;

  // ── 搜索 ──
  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  // ── 标签 ──
  List<Tag> _allTags = [];
  List<Tag> get allTags => _allTags;
  final Map<int, List<Tag>> _trackTags = {};
  /// 每个曲目的标签切换排队串行执行，见 [toggleTagOnTrack]。
  final Map<int, Future<void>> _tagToggleChains = {};
  // ── 曲目多选 ──
  final Set<int> _selectedTrackIds = {};
  /// 只读视图：调用方拿不到内部集合，改不到选中状态。
  Set<int> get selectedTrackIds => UnmodifiableSetView(_selectedTrackIds);
  int? _anchorTrackId;
  bool _selectionMode = false;
  bool get selectionMode => _selectionMode;
  bool isTrackSelected(int id) => _selectedTrackIds.contains(id);
  TagFilter _tagFilter = const TagFilter();
  TagFilter get tagFilter => _tagFilter;
  String _advancedFilter = '';
  String get advancedFilter => _advancedFilter;
  bool get hasAdvancedFilter => _advancedFilter.trim().isNotEmpty;

  // ── 导入状态 ──
  bool _importing = false;
  bool get importing => _importing;
  double _importProgress = 0;
  double get importProgress => _importProgress;

  /// 最近一次导入的失败原因；null 表示上次导入没有出错。
  ///
  /// 导入的调用方是按钮回调，没有错误边界，所以不往上抛异常；改成把这个字段
  /// 交给界面，让失败可见，而不是只写一行日志当没事发生。
  String? _importError;
  String? get importError => _importError;

  // ── 最近播放 ──
  List<TrackItem> _recentTracks = [];
  List<TrackItem> get recentTracks => _recentTracks;
  /// [loadRecentTracks] 的代际：快速切歌会并发触发多次重载，只有最后一次能写回。
  int _recentLoadGeneration = 0;

  // ── 播放队列来源作品的封面 ──
  String? _playingWorkCover;
  /// 当前播放队列来源作品的封面。队列建立时记录，与「当前浏览的作品」解耦。
  String? get playingWorkCover => _playingWorkCover;

  // ── 封面缓存上限（MB，0 表示不限制）──
  int _coverCacheLimitMB = 512;
  int get coverCacheLimitMB => _coverCacheLimitMB;

  // ── 设置 ──
  ThemeMode _themeMode = ThemeMode.dark;
  ThemeMode get themeMode => _themeMode;
  String _sortKey = 'filename';
  String get sortKey => _sortKey;
  bool _sortDescending = false;
  bool get sortDescending => _sortDescending;

  // ── 字幕缓存 ──
  final Map<String, List<LyricLine>> _subtitleCache = {};

  // ═══════════════ DAO 便捷访问 ═══════════════

  WorkDao get _workDao => WorkDao(DatabaseManager.instance.db);
  FolderDao get _folderDao => FolderDao(DatabaseManager.instance.db);
  TrackDao get _trackDao => TrackDao(DatabaseManager.instance.db);
  TagDao get _tagDao => TagDao(DatabaseManager.instance.db);

  AppState({required this.player});

  Future<void> init() async {
    logInfo('AppState', 'Initializing...');
    player.onTrackStarted = _onTrackStarted;
    await loadSettings();
    await loadTags();
    await loadRecentTracks();
    await loadCoverCacheLimit();
    await refresh();
    logInfo('AppState', 'Initialized OK');
  }

  // ═══════════════ 设置 ═══════════════

  Future<void> loadSettings() async {
    final ss = SettingsService.instance;
    _themeMode = ss.themeMode;
    _sortKey = ss.sortKey;
    _sortDescending = ss.sortDescending;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await SettingsService.instance.setThemeMode(mode);
    notifyListeners();
  }

  Future<void> setSortKey(String key) async {
    _sortKey = key;
    await SettingsService.instance.setSortKey(key);
    await refresh();
  }

  Future<void> setSortDescending(bool desc) async {
    _sortDescending = desc;
    await SettingsService.instance.setSortDescending(desc);
    await refresh();
  }

  // ═══════════════ 刷新 / 中间栏加载 ═══════════════

  /// 每次 refresh 递增。用于丢弃「先发起但后完成」的旧结果。
  int _refreshGeneration = 0;

  Future<void> refresh() async {
    final gen = ++_refreshGeneration;
    logInfo('AppState', 'refresh() gen=$gen');
    _subtitleCache.clear();
    final works = await _workDao.listAll();
    final unassigned = await _folderDao.listUnassignedRoots();
    if (gen != _refreshGeneration) {
      logInfo('AppState', 'refresh() gen=$gen 已被新一代取代，丢弃结果');
      return;
    }
    _works = works;
    _unassignedFolders = unassigned;
    notifyListeners();
    await _loadCenter(gen);
  }

  /// 加载中间栏。[gen] 是发起时的 [refresh] 代际。
  Future<void> _loadCenter(int gen) async {
    _loading = true;
    notifyListeners();
    try {
      final search = _searchQuery.trim();
      final filterActive = hasAdvancedFilter || _tagFilter.active;

      List<VirtualFolder> folders;
      List<TrackItem> tracks;

      if (search.isNotEmpty) {
        folders = const [];
        var list = await _trackDao.searchByName(search);
        if (filterActive) {
          final ids = await _computeMatchingIds();
          list = list.where((t) => ids.contains(t.id)).toList();
        }
        tracks = list;
      } else {
        if (_currentWork != null && _currentFolderId != null) {
          folders = await _folderDao.listChildren(_currentFolderId!);
          tracks = _currentFolderPath == null
              ? <TrackItem>[]
              : await _trackDao.queryDirectInDir(_currentFolderPath!);
        } else if (_currentWork != null) {
          // 严格按文件夹树：作品层只显示入口子文件夹，不直接平铺曲目
          folders = await _folderDao.listRootsByWork(_currentWork!.id!);
          tracks = const [];
        } else {
          folders = const [];
          tracks = const [];
        }

        if (filterActive) {
          final ids = await _computeMatchingIds();
          tracks = tracks.where((t) => ids.contains(t.id)).toList();
          folders = await _filterFolders(folders, ids);
        }
      }

      // 等待期间又有新的 refresh 发起，本次结果作废，不覆盖更新的状态。
      if (gen != _refreshGeneration) {
        logInfo('AppState', 'Center load gen=$gen 已被取代，丢弃结果');
        return;
      }
      _centerFolders = _sortFolders(folders);
      _tracks = _sortTracks(tracks);
      // 选中集合只保留当前可见的曲目。切到别的作品或文件夹之后，
      // 「批量打标签」「移动」不会落到看不见的曲目上。
      final visibleIds = _tracks.map((t) => t.id).whereType<int>().toSet();
      final selectedBefore = _selectedTrackIds.length;
      _selectedTrackIds.retainAll(visibleIds);
      if (_anchorTrackId != null && !visibleIds.contains(_anchorTrackId)) {
        _anchorTrackId = null;
      }
      if (_selectedTrackIds.isEmpty) _selectionMode = false;
      if (selectedBefore != _selectedTrackIds.length) {
        logInfo('AppState',
            '选中集合随上下文收窄: $selectedBefore -> ${_selectedTrackIds.length}');
      }
      logInfo('AppState',
          'Center loaded: ${_centerFolders.length} folders, ${_tracks.length} tracks');
    } finally {
      // 只有最新一代有资格清 loading，否则会提前关掉新一轮的转圈。
      if (gen == _refreshGeneration) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<Set<int>> _computeMatchingIds() async {
    if (hasAdvancedFilter) {
      return _tagDao.getTrackIdsByExpression(_advancedFilter, _allTags);
    }
    return _tagDao.getTrackIdsByTags(
      andTagIds: _tagFilter.andTagIds,
      orTagIds: _tagFilter.orTagIds,
      notTagIds: _tagFilter.notTagIds,
    );
  }

  Future<List<VirtualFolder>> _filterFolders(
      List<VirtualFolder> folders, Set<int> matchingIds) async {
    if (folders.isEmpty) return [];
    final matchingPaths =
        matchingIds.isEmpty ? <String>[] : await _trackDao.pathsByIds(matchingIds);

    Map<int, List<Tag>> folderTags = {};
    if (!hasAdvancedFilter && _tagFilter.active) {
      folderTags =
          await _tagDao.getTagsForFolders(folders.map((f) => f.id!).toList());
    }

    final result = <VirtualFolder>[];
    for (final f in folders) {
      final paths = await _folderDao.getPaths(f.id!);
      final containsTrack =
          paths.any((p) => matchingPaths.any((mp) => _isUnderPath(mp, p.path)));
      if (containsTrack) {
        result.add(f);
        continue;
      }
      if (!hasAdvancedFilter && _tagFilter.active) {
        final tags = folderTags[f.id] ?? const <Tag>[];
        if (_folderTagsMatch(tags)) result.add(f);
      }
    }
    return result;
  }

  bool _folderTagsMatch(List<Tag> tags) {
    final ids = tags.map((t) => t.id).whereType<int>().toSet();
    if (_tagFilter.andTagIds.any((id) => !ids.contains(id))) return false;
    if (_tagFilter.orTagIds.isNotEmpty &&
        !_tagFilter.orTagIds.any((id) => ids.contains(id))) {
      return false;
    }
    if (_tagFilter.notTagIds.any((id) => ids.contains(id))) return false;
    return true;
  }

  bool _isUnderPath(String path, String dir) {
    final a = path.toLowerCase();
    var b = dir.toLowerCase();
    if (b.endsWith('\\') || b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    if (a == b) return false;
    return a.startsWith('$b\\') || a.startsWith('$b/');
  }

  List<VirtualFolder> _sortFolders(List<VirtualFolder> list) {
    // 先复制：入参可能是 const []（不可变），直接 sort 会抛 Unsupported operation
    final sorted = List<VirtualFolder>.from(list);
    sorted.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return sorted;
  }

  List<TrackItem> _sortTracks(List<TrackItem> list) {
    final sorted = List<TrackItem>.from(list);
    final dir = _sortDescending ? -1 : 1;
    sorted.sort((a, b) {
      int cmp;
      switch (_sortKey) {
        case 'title':
          cmp = a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase());
          break;
        case 'duration':
          cmp = (a.durationMs ?? 0).compareTo(b.durationMs ?? 0);
          break;
        case 'added_at':
          cmp = a.addedAt.compareTo(b.addedAt);
          break;
        default:
          cmp = a.filename.toLowerCase().compareTo(b.filename.toLowerCase());
          break;
      }
      if (cmp == 0) {
        cmp = a.filename.toLowerCase().compareTo(b.filename.toLowerCase());
      }
      return cmp * dir;
    });
    return sorted;
  }

  // ═══════════════ 搜索 ═══════════════

  void setSearchQuery(String q) {
    _searchQuery = q;
    refresh();
  }

  // ═══════════════ 导航 ═══════════════

  Future<void> goHome() async {
    _currentWork = null;
    _currentFolderId = null;
    _currentFolder = null;
    _currentFolderPath = null;
    _breadcrumb = [];
    await refresh();
  }

  Future<void> enterWork(int workId) async {
    final work = await _workDao.getById(workId);
    if (work == null) return;
    _currentWork = work;
    _currentFolderId = null;
    _currentFolder = null;
    _currentFolderPath = null;
    _breadcrumb = [VirtualFolder(id: -1, name: work.name, workId: work.id)];
    await refresh();
  }

  Future<void> enterFolder(int folderId) async {
    final folder = await _folderDao.getById(folderId);
    if (folder == null) return;
    _currentFolderId = folderId;
    _currentFolder = folder;
    final paths = await _folderDao.getPaths(folderId);
    _currentFolderPath = paths.isEmpty ? null : paths.first.path;
    // 若文件夹属于某作品，确保 currentWork 一致
    if (folder.workId != null && _currentWork?.id != folder.workId) {
      final w = await _workDao.getById(folder.workId!);
      if (w != null) _currentWork = w;
    }
    _breadcrumb = await _buildBreadcrumb();
    await refresh();
  }

  Future<void> goUp() async {
    if (_currentFolderId == null) {
      await enterWorkOrHome();
      return;
    }
    final parent = _currentFolder?.parentId;
    if (parent == null) {
      // 回到作品层
      if (_currentWork != null) {
        await enterWork(_currentWork!.id!);
      } else {
        await goHome();
      }
      return;
    }
    await enterFolder(parent);
  }

  Future<void> enterWorkOrHome() async {
    if (_currentWork != null) {
      await enterWork(_currentWork!.id!);
    } else {
      await goHome();
    }
  }

  Future<List<VirtualFolder>> _buildBreadcrumb() async {
    final work = _currentWork;
    final chain = <VirtualFolder>[];
    var cur = _currentFolder;
    while (cur != null) {
      chain.insert(0, cur);
      if (cur.parentId == null) break;
      cur = await _folderDao.getById(cur.parentId!);
    }
    // work 作为首层标记
    if (work != null) {
      chain.insert(
          0,
          VirtualFolder(
              id: -1, name: work.name, parentId: null, workId: work.id));
    }
    return chain;
  }

  // ═══════════════ 作品集操作 ═══════════════

  Future<Work> createWork(String name) async {
    final work = await _workDao.create(name);
    await refresh();
    return work;
  }

  Future<void> renameWork(int id, String name) async {
    await _workDao.rename(id, name);
    if (_currentWork?.id == id) {
      _currentWork = Work(
          id: id,
          name: name,
          coverPath: _currentWork!.coverPath,
          createdAt: _currentWork!.createdAt);
    }
    await refresh();
  }

  Future<void> deleteWork(int id) async {
    // WorkDao.delete 内部用事务完成「摘归属 + 删作品」。
    await _workDao.delete(id);
    if (_currentWork?.id == id) {
      await goHome();
    } else {
      await refresh();
    }
  }

  Future<void> setWorkCover(int id, String? coverPath) async {
    await _workDao.setCover(id, coverPath);
    if (_currentWork?.id == id) {
      _currentWork = Work(
          id: id,
          name: _currentWork!.name,
          coverPath: coverPath,
          createdAt: _currentWork!.createdAt);
    }
    notifyListeners();
    await refresh();
  }

  // ═══════════════ 文件夹操作 ═══════════════

  Future<void> renameFolder(int id, String newName) async {
    await _folderDao.rename(id, newName);
    _folderVersion++;
    await refresh();
  }

  Future<void> deleteFolder(int id) async {
    // 先记下这个文件夹自己挂在哪几条路径上：删完之后 folder_paths 会被 CASCADE 清掉，
    // 再想问「哪些曲目本来是靠它才可见的」就没有依据了。
    final removedPaths =
        (await _folderDao.getPaths(id)).map((fp) => fp.path).toList();
    await _folderDao.delete(id);
    await _pruneTracksLeftBehind(removedPaths);
    _folderVersion++;
    if (_currentFolderId == id) {
      _currentFolderId = null;
      _currentFolder = null;
      _currentFolderPath = null;
    }
    await refresh();
  }

  /// 删除文件夹后，把「落在被删路径下、又不再被任何文件夹覆盖」的曲目从曲库移除。
  ///
  /// 曲目行只通过 folder_paths 里的路径前缀可见。留下这些孤儿行会同时坏两件事：
  /// 搜索能搜到但树里进不去；同一个目录再导入会被「全部已入库」挡掉，
  /// 于是那个目录永远挂不回来。
  ///
  /// 返回实际删除的曲目行数。
  Future<int> _pruneTracksLeftBehind(List<String> removedPaths) async {
    if (removedPaths.isEmpty) return 0;

    final alive = <String>[];
    for (final list in (await _folderDao.getAllPaths()).values) {
      for (final fp in list) {
        alive.add(fp.path);
      }
    }

    final orphan = <String>[];
    for (final track in await _trackDao.queryAll()) {
      final wasInside = removedPaths.any((r) => p.isWithin(r, track.path));
      if (!wasInside) continue;
      // 还有别的文件夹挂着它的上级目录，就留着。
      if (alive.any((a) => p.isWithin(a, track.path))) continue;
      orphan.add(track.path);
    }
    if (orphan.isEmpty) return 0;

    final deleted = await _trackDao.deleteByPaths(orphan);
    _trackTags.clear();
    logInfo('AppState',
        '删除文件夹后清理失联曲目 ${orphan.length} 条（实删 $deleted 行）');
    return deleted;
  }

  /// 把文件夹（及其后代）移动到另一作品
  Future<void> moveFolderToWork(int folderId, int? workId) async {
    final ids = await _folderDao.collectDescendants(folderId);
    await _folderDao.setWorkMany(ids, workId);
    _folderVersion++;
    await refresh();
  }

  Future<List<Work>> loadWorks() => _workDao.listAll();

  // ═══════════════ 导入 ═══════════════

  /// 导入目录（自动创建同名作品）。
  ///
  /// 返回 null 表示没有导入：已有别的导入在跑，或者目录里没有新的音频。
  /// 目录内没有音频时不建作品，避免留下空作品。
  Future<Work?> importDirectory(String dirPath) async {
    if (!_beginImport('importDirectory')) return null;
    try {
      final scan = await FileScanner.scanDirectoryOffThread(dirPath);
      if (scan.audioPaths.isEmpty) {
        logWarn('AppState', '目录内无音频，未创建作品: $dirPath');
        return null;
      }
      if (!await _hasNewAudio(scan)) {
        logWarn('AppState', '目录内音频均已导入，未创建作品: $dirPath');
        return null;
      }

      final work = await _workDao.create(_baseName(dirPath));
      final imported = await _runImport(dirPath, work.id!, scan: scan);
      if (imported == 0) {
        // 一条都没落库就删掉刚建的作品：可能是并发插入被 UNIQUE 忽略，
        // 也可能是这次导入直接失败（建树失败时曲目还没开始写，所以也是 0）。
        // 失败原因留在 _importError 里给界面显示。
        final why = _importError ?? '没有新曲目落库';
        logWarn('AppState', '导入没有落库（$why），删除空作品: ${work.name}');
        await _workDao.delete(work.id!);
        return null;
      }
      return work;
    } finally {
      _endImport();
    }
  }

  /// 导入目录到指定作品（合并）
  Future<void> importDirectoryIntoWork(String dirPath, int workId) async {
    if (!_beginImport('importDirectoryIntoWork')) return;
    try {
      await _runImport(dirPath, workId);
    } finally {
      _endImport();
    }
  }

  /// 是否至少有一首曲目还没入库。
  Future<bool> _hasNewAudio(ScanResult scan) async {
    final existing = await _trackDao.existingPaths(scan.audioPaths);
    return existing.length < scan.audioPaths.length;
  }

  /// 同步置位导入标志，返回 false 表示本次请求被拒。
  ///
  /// 标志必须在第一个 await 之前置上：两次导入同时进来时，第二次要在这里就被挡住，
  /// 不能等 `_runImport` 里再判断。
  bool _beginImport(String caller) {
    if (_importing) {
      logWarn('AppState', '$caller: 已有导入进行中，忽略本次请求');
      return false;
    }
    _importing = true;
    _importProgress = 0;
    _importError = null;
    notifyListeners();
    return true;
  }

  void _endImport() {
    _importing = false;
    _importProgress = 0;
    notifyListeners();
  }

  /// 真正干活的部分。调用方负责用 [_beginImport] / [_endImport] 圈住导入期。
  /// 返回处理过的新曲目数，0 表示这次导入没有新增内容。
  Future<int> _runImport(String dirPath, int workId, {ScanResult? scan}) async {
    var imported = 0;
    try {
      final importService = ImportService.fromDB();
      final stream =
          importService.importDirectory(dirPath, workId: workId, scan: scan);
      await for (final p in stream) {
        imported++;
        _importProgress = p.percent;
        notifyListeners();
      }
    } catch (e) {
      _importError = e.toString();
      logError('AppState', '导入失败', e.toString());
    } finally {
      _importProgress = 0;
      notifyListeners();
      _folderVersion++;
      await refresh();
      await enforceCoverCacheLimit();
    }
    return imported;
  }

  String _baseName(String path) {
    final idx = path.lastIndexOf(RegExp(r'[\\/]'));
    final base = idx >= 0 ? path.substring(idx + 1) : path;
    return base.isEmpty ? path : base;
  }

  // ═══════════════ 标签 ═══════════════

  Future<void> loadTags() async {
    _allTags = await _tagDao.getAll();
    notifyListeners();
  }

  Future<List<Tag>> getTrackTags(int trackId) async {
    final cached = _trackTags[trackId];
    if (cached != null) return List<Tag>.unmodifiable(cached);
    final tags = await _tagDao.getTagsForTrack(trackId);
    _trackTags[trackId] = List<Tag>.of(tags);
    return List<Tag>.unmodifiable(_trackTags[trackId]!);
  }

  /// 切换曲目标签。同一曲目的多次调用按顺序串行执行。
  ///
  /// 连点两次同一个标签时，第二次必须在第一次写库并更新缓存之后才读当前状态；
  /// 否则两次都读到「未打标签」，双击「关标签」会变成打开。
  Future<void> toggleTagOnTrack(int trackId, Tag tag) {
    final previous = _tagToggleChains[trackId] ?? Future<void>.value();
    final chain = previous.then((_) => _applyTagToggle(trackId, tag));
    // 链尾只保留不会失败的 future：前一次出错不能卡住后面的点击。
    final tail = chain.catchError((Object _) {});
    _tagToggleChains[trackId] = tail;
    unawaited(tail.whenComplete(() {
      if (identical(_tagToggleChains[trackId], tail)) {
        _tagToggleChains.remove(trackId);
      }
    }));
    return chain;
  }

  Future<void> _applyTagToggle(int trackId, Tag tag) async {
    // 改副本，缓存里的 List 不被就地修改；调用方拿到的也是不可变视图。
    final current = List<Tag>.of(
        _trackTags[trackId] ?? await _tagDao.getTagsForTrack(trackId));
    final has = current.any((t) => t.id == tag.id);
    if (has) {
      await _tagDao.removeTagFromTrack(trackId, tag.id!);
      current.removeWhere((t) => t.id == tag.id);
    } else {
      await _tagDao.addTagToTrack(trackId, tag.id!);
      current.add(tag);
    }
    _trackTags[trackId] = current;
    notifyListeners();
  }

  Future<void> addTagToFolder(int folderId, Tag tag) async {
    await addTagsToFolder(folderId, [tag]);
  }

  /// 为文件夹批量添加标签；[recursive] 为真时递归同步到其所有子文件夹曲目。
  Future<void> addTagsToFolder(int folderId, List<Tag> tags,
      {bool recursive = false}) async {
    for (final tag in tags) {
      await _tagDao.addTagToFolder(folderId, tag.id!);
    }
    if (recursive) {
      final trackIds = await _collectFolderTrackIds(folderId);
      await _tagDao.addTagsToTracks(trackIds, tags.map((t) => t.id!));
    }
    _folderVersion++;
    notifyListeners();
  }

  Future<void> removeTagsFromFolder(int folderId, List<Tag> tags,
      {bool recursive = false}) async {
    if (recursive) {
      final trackIds = await _collectFolderTrackIds(folderId);
      await _tagDao.removeTagsFromTracks(trackIds, tags.map((t) => t.id!));
    }
    for (final tag in tags) {
      await _tagDao.removeTagFromFolder(folderId, tag.id!);
    }
    _folderVersion++;
    notifyListeners();
  }

  /// 收集文件夹及其所有子文件夹下的曲目 id（按路径前缀）
  Future<Set<int>> _collectFolderTrackIds(int folderId) async {
    final paths = <String>[];
    final queue = <int>[folderId];
    while (queue.isNotEmpty) {
      final fid = queue.removeAt(0);
      for (final fp in await _folderDao.getPaths(fid)) {
        paths.add(fp.path);
      }
      for (final c in await _folderDao.listChildren(fid)) {
        if (c.id != null) queue.add(c.id!);
      }
    }
    if (paths.isEmpty) return {};
    final tracks = await _trackDao.queryByDirs(paths);
    return tracks.map((t) => t.id).whereType<int>().toSet();
  }

  Future<List<Tag>> getFolderTags(int folderId) =>
      _tagDao.getTagsForFolder(folderId);

  Future<Tag> createTag(String name,
      {String namespace = '', String color = '#cba6f7'}) async {
    final ns = namespace.isEmpty ? 'general' : namespace;
    final match = _allTags.where((t) =>
        t.name.toLowerCase() == name.toLowerCase() && t.namespace == ns);
    if (match.isNotEmpty) return match.first;
    final tag = await _tagDao.insert(Tag(name: name, namespace: ns, color: color));
    await loadTags();
    return tag;
  }

  Future<void> deleteTag(int tagId) async {
    await _tagDao.delete(tagId);
    _trackTags.clear();
    _removeFromFilter(tagId);
    await loadTags();
    await refresh();
  }

  /// 更新标签（重命名 / 改命名空间 / 改色）
  Future<void> updateTag(int tagId, String name,
      {String? namespace, String? color}) async {
    final existing = await _tagDao.getById(tagId);
    if (existing == null) return;
    await _tagDao.update(Tag(
      id: tagId,
      namespace: namespace ?? existing.namespace,
      name: name,
      color: color ?? existing.color,
    ));
    _trackTags.clear();
    await loadTags();
    await refresh();
  }

  // ═══════════════ 曲目多选 + 批量标签 ═══════════════

  void toggleTrackSelect(int id) {
    if (_selectedTrackIds.contains(id)) {
      _selectedTrackIds.remove(id);
    } else {
      _selectedTrackIds.add(id);
    }
    _anchorTrackId = id;
    notifyListeners();
  }

  void rangeTrackSelect(int id) {
    final list = _tracks;
    final anchorIdx = _anchorTrackId == null
        ? -1
        : list.indexWhere((t) => t.id == _anchorTrackId);
    final curIdx = list.indexWhere((t) => t.id == id);
    if (anchorIdx < 0 || curIdx < 0) {
      toggleTrackSelect(id);
      return;
    }
    final lo = anchorIdx < curIdx ? anchorIdx : curIdx;
    final hi = anchorIdx < curIdx ? curIdx : anchorIdx;
    for (final t in list.sublist(lo, hi + 1)) {
      if (t.id != null) _selectedTrackIds.add(t.id!);
    }
    _anchorTrackId = id;
    notifyListeners();
  }

  /// 长按进入多选模式（移动端）；桌面 Ctrl+点击也可走此路径
  void enterSelectionMode(int id) {
    _selectionMode = true;
    _selectedTrackIds.add(id);
    _anchorTrackId = id;
    notifyListeners();
  }

  void clearTrackSelection() {
    _selectionMode = false;
    _selectedTrackIds.clear();
    _anchorTrackId = null;
    notifyListeners();
  }

  Future<void> addTagsToTracks(Iterable<int> trackIds, List<Tag> tags) async {
    await _tagDao.addTagsToTracks(trackIds, tags.map((t) => t.id!));
    _trackTags.clear();
    notifyListeners();
  }

  Future<void> removeTagsFromTracks(
      Iterable<int> trackIds, List<Tag> tags) async {
    await _tagDao.removeTagsFromTracks(trackIds, tags.map((t) => t.id!));
    _trackTags.clear();
    notifyListeners();
  }

  /// 返回这批曲目上已绑定的标签 id 集合（用于「移除标签」时过滤可选项）
  Future<Set<int>> getTagIdsOnTracks(Iterable<int> trackIds) async {
    final ids = trackIds.toList();
    if (ids.isEmpty) return {};
    final map = await _tagDao.getTagsForTracks(ids);
    final result = <int>{};
    for (final tags in map.values) {
      for (final t in tags) {
        if (t.id != null) result.add(t.id!);
      }
    }
    return result;
  }

  void _removeFromFilter(int tagId) {
    _tagFilter = TagFilter(
      andTagIds: _tagFilter.andTagIds.where((id) => id != tagId).toList(),
      orTagIds: _tagFilter.orTagIds.where((id) => id != tagId).toList(),
      notTagIds: _tagFilter.notTagIds.where((id) => id != tagId).toList(),
    );
  }

  // 标签筛选
  void toggleAndFilter(int tagId) {
    _advancedFilter = '';
    final list = List<int>.from(_tagFilter.andTagIds);
    list.contains(tagId) ? list.remove(tagId) : list.add(tagId);
    _tagFilter = TagFilter(
      andTagIds: list,
      orTagIds: _tagFilter.orTagIds.where((id) => id != tagId).toList(),
      notTagIds: _tagFilter.notTagIds.where((id) => id != tagId).toList(),
    );
    refresh();
  }

  void toggleOrFilter(int tagId) {
    _advancedFilter = '';
    final list = List<int>.from(_tagFilter.orTagIds);
    list.contains(tagId) ? list.remove(tagId) : list.add(tagId);
    _tagFilter = TagFilter(
      andTagIds: _tagFilter.andTagIds.where((id) => id != tagId).toList(),
      orTagIds: list,
      notTagIds: _tagFilter.notTagIds.where((id) => id != tagId).toList(),
    );
    refresh();
  }

  void toggleNotFilter(int tagId) {
    _advancedFilter = '';
    final list = List<int>.from(_tagFilter.notTagIds);
    list.contains(tagId) ? list.remove(tagId) : list.add(tagId);
    _tagFilter = TagFilter(
      andTagIds: _tagFilter.andTagIds.where((id) => id != tagId).toList(),
      orTagIds: _tagFilter.orTagIds.where((id) => id != tagId).toList(),
      notTagIds: list,
    );
    refresh();
  }

  void clearTagFilters() {
    _tagFilter = const TagFilter();
    refresh();
  }

  Future<void> setAdvancedFilter(String expression) async {
    final expr = expression.trim();
    if (expr.isEmpty) {
      await clearAdvancedFilter();
      return;
    }
    FilterExpressionParser.parse(expr);
    _advancedFilter = expr;
    _tagFilter = const TagFilter();
    await SettingsService.instance.addExpression(expr);
    await refresh();
  }

  Future<void> clearAdvancedFilter() async {
    if (!hasAdvancedFilter) return;
    _advancedFilter = '';
    await refresh();
  }

  // ═══════════════ 播放 ═══════════════

  /// 播放当前列表从 [startIndex] 开始
  Future<void> playTracks(List<TrackItem> list, int startIndex) async {
    _rememberQueueCover();
    await player.playQueue(list, startIndex: startIndex);
  }

  Future<void> playAllCurrent() async {
    if (_tracks.isEmpty) return;
    _rememberQueueCover();
    await player.playQueue(_tracks, startIndex: 0);
  }

  Future<void> playTrackAt(int index) async {
    if (index < 0 || index >= _tracks.length) return;
    _rememberQueueCover();
    await player.playQueue(_tracks, startIndex: index);
  }

  // ═══════════════ 字幕 / 封面 ═══════════════

  List<LyricLine> getSubtitleLines(TrackItem track) {
    final p = track.subtitlePath;
    if (p == null || p.isEmpty) return const [];
    return _subtitleCache.putIfAbsent(
        track.path, () => SubtitleParser.parseFile(p));
  }

  Future<void> replaceSubtitle(int trackId, String newPath) async {
    await _trackDao.setSubtitlePath(trackId, newPath);
    _subtitleCache.clear();
    // 更新内存中的曲目
    _tracks = _tracks
        .map((t) => t.id == trackId
            ? t.copyWith(subtitlePath: newPath)
            : t)
        .toList();
    notifyListeners();
  }

  Future<void> clearSubtitle(int trackId) async {
    await _trackDao.setSubtitlePath(trackId, null);
    _subtitleCache.clear();
    _tracks = _tracks
        .map((t) => t.id == trackId ? t.copyWith(subtitlePath: null) : t)
        .toList();
    notifyListeners();
  }

  /// 当前曲目封面：优先队列来源作品的封面，否则曲目内嵌封面。
  ///
  /// 用播放队列建立时记下的作品封面，而不是「当前浏览的作品」，
  /// 播放中切换浏览对象不会把播放栏与通知栏的封面换掉。
  String? coverForTrack(TrackItem track) {
    final wc = _playingWorkCover;
    if (wc != null && File(wc).existsSync()) return wc;
    if (track.coverPath != null && File(track.coverPath!).existsSync()) {
      return track.coverPath;
    }
    return null;
  }

  /// 记下这次播放队列对应的作品封面。
  void _rememberQueueCover() {
    final cover = _currentWork?.coverPath;
    _playingWorkCover =
        (cover != null && File(cover).existsSync()) ? cover : null;
  }

  /// 按当前浏览的作品记录播放队列来源封面。
  ///
  /// 播放入口在调 `player.playQueue` 之前都会先调它；测试里用它绕过原生播放器。
  @visibleForTesting
  void rememberQueueSource() => _rememberQueueCover();

  // ═══════════════ 数据目录 ═══════════════

  Future<String> getDataDir() => DataDirService.instance.dataDir;

  bool _migrating = false;

  /// 迁移数据目录到 [newDir]：关闭数据库 → 复制数据 → 重开数据库 → 刷新。
  ///
  /// 同一时刻只允许一次迁移。中途失败时把数据库重开到「指针指向的目录」，
  /// 不让应用停在「库已关闭」的状态。
  Future<void> migrateDataDir(String newDir) async {
    if (_migrating) {
      throw StateError('数据目录迁移已在进行中');
    }
    _migrating = true;
    final oldDir = await DataDirService.instance.dataDir;
    try {
      await DatabaseManager.instance.close();
      final newD = await DataDirService.instance.migrateTo(newDir);
      await DatabaseManager.instance.init();
      // 更新数据目录内的封面缓存路径前缀（covers/track_*.jpg、covers/work_*.jpg）
      await _rewriteCoverPaths(oldDir, newD);
      await loadSettings();
      await loadTags();
      await refresh();
      logInfo('AppState', '数据目录迁移完成: $oldDir -> $newD');
    } catch (e, st) {
      logError('AppState', '数据目录迁移失败: $e\n$st');
      // migrateTo 成功则指针已指向新目录，失败则仍指向旧目录；两种情况都按指针
      // 重开，避免数据库一直处于关闭状态。
      if (!DatabaseManager.instance.isOpen) {
        try {
          await DatabaseManager.instance.init();
        } catch (reopenErr) {
          logError('AppState', '迁移失败后重开数据库也失败: $reopenErr');
        }
      }
      rethrow;
    } finally {
      _migrating = false;
    }
  }

  /// 把指向旧数据目录的封面路径改写为新数据目录（目录外的原图路径不动）
  Future<void> _rewriteCoverPaths(String oldDir, String newDir) async {
    final tracks = await _trackDao.queryAll();
    for (final t in tracks) {
      final moved = _movedPath(t.coverPath, oldDir, newDir);
      if (moved != null) await _trackDao.setCoverPath(t.id!, moved);
    }
    final works = await _workDao.listAll();
    for (final w in works) {
      final moved = _movedPath(w.coverPath, oldDir, newDir);
      if (moved != null) await _workDao.setCover(w.id!, moved);
    }
  }

  /// [path] 在 [oldDir] 之内时返回它在新目录下的对应路径，否则返回 null。
  /// 用 p.isWithin 判断，避免 `/a/b` 误匹配 `/a/bc/...`。
  String? _movedPath(String? path, String oldDir, String newDir) {
    if (path == null) return null;
    if (!p.isWithin(oldDir, path)) return null;
    return p.join(newDir, p.relative(path, from: oldDir));
  }

  // ═══════════════ 最近播放 / 播放历史 ═══════════════

  void _onTrackStarted(TrackItem track) {
    final id = track.id;
    if (id == null) return;
    final gen = ++_recentLoadGeneration;
    unawaited(_trackDao
        .recordPlay(id, DateTime.now().millisecondsSinceEpoch)
        .then((_) => _reloadRecentTracks(gen))
        .catchError((Object e) {
      logError('AppState', 'recordPlay 失败: $e');
    }));
  }

  Future<void> loadRecentTracks() => _reloadRecentTracks(_recentLoadGeneration);

  /// 只有最后一次触发的重载能写回结果。
  ///
  /// 快速切歌会并发触发多次 recordPlay 与多次重载，先发起的那次可能后完成。
  Future<void> _reloadRecentTracks(int gen) async {
    final list = await _trackDao.recentPlayedTracks();
    if (gen != _recentLoadGeneration) {
      logInfo('AppState', 'recent gen=$gen 已被取代，丢弃结果');
      return;
    }
    _recentTracks = list;
    notifyListeners();
  }

  Future<void> playRecentTracks(int startIndex) async {
    if (_recentTracks.isEmpty) return;
    // 最近播放跨作品，没有单一来源封面，回退到每首曲目自己的封面。
    _playingWorkCover = null;
    await player.playQueue(_recentTracks, startIndex: startIndex);
  }

  // ═══════════════ 封面缓存管理 ═══════════════

  Future<void> loadCoverCacheLimit() async {
    _coverCacheLimitMB = SettingsService.instance.coverCacheLimitMB;
  }

  Future<int> getCoverCacheSizeBytes() =>
      CoverService.embeddedCacheSizeBytes();

  Future<int> clearCoverCache() async {
    final freed = await CoverService.clearEmbeddedCache();
    notifyListeners();
    return freed;
  }

  Future<void> setCoverCacheLimit(int mb) async {
    _coverCacheLimitMB = mb.clamp(0, 8192);
    await SettingsService.instance.setCoverCacheLimitMB(_coverCacheLimitMB);
    if (_coverCacheLimitMB > 0) {
      await CoverService.enforceLimit(_coverCacheLimitMB * 1024 * 1024,
          keep: _protectedCoverPaths());
    }
    notifyListeners();
  }

  Future<void> enforceCoverCacheLimit() async {
    if (_coverCacheLimitMB <= 0) return;
    await CoverService.enforceLimit(_coverCacheLimitMB * 1024 * 1024,
        keep: _protectedCoverPaths());
  }

  /// 清理封面缓存时不能删的封面：正在播放的曲目、当前浏览作品的封面
  Set<String> _protectedCoverPaths() {
    final keep = <String>{};
    final playing = player.currentTrack?.coverPath;
    if (playing != null) keep.add(playing);
    final work = _currentWork?.coverPath;
    if (work != null) keep.add(work);
    return keep;
  }
}
