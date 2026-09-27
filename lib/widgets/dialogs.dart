import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/tag_dao.dart';
import '../services/cover_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// 未归类作品哨兵值
const int kUnassignedWork = -1;

/// 文本输入对话框
Future<String?> promptText(BuildContext context,
    {required String title, String initial = '', String hint = ''}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _PromptDialog(title: title, initial: initial, hint: hint),
  );
}

Future<bool?> confirmDialog(BuildContext context,
    {required String title, required String content, String okLabel = '确定'}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(content,
          style: TextStyle(color: AppColors.textSecondaryOf(ctx), fontSize: 13)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true), child: Text(okLabel)),
      ],
    ),
  );
}

/// 选择封面图片文件，返回路径
Future<String?> pickImagePath() async {
  final f = await FilePicker.pickFile(
      type: FileType.image, dialogTitle: '选择封面图片');
  return f?.path;
}

/// 选择字幕文件，返回路径
Future<String?> pickSubtitlePath() async {
  final f = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['vtt', 'srt', 'lrc'],
      dialogTitle: '选择字幕文件');
  return f?.path;
}

/// 选择文件夹，返回路径
Future<String?> pickDirectoryPath({String? title}) async {
  return FilePicker.getDirectoryPath(dialogTitle: title ?? '选择文件夹');
}

/// 导入封面并设置到作品
Future<void> showImportCoverDialog(BuildContext context, int workId) async {
  final appState = context.read<AppState>();
  final src = await pickImagePath();
  if (src == null) return;
  final dest = await CoverService.importCover(src, workId);
  if (dest != null) {
    await appState.setWorkCover(workId, dest);
  }
}

/// 替换当前曲目字幕
Future<void> showReplaceSubtitleDialog(BuildContext context, int trackId) async {
  final appState = context.read<AppState>();
  final path = await pickSubtitlePath();
  if (path == null) return;
  await appState.replaceSubtitle(trackId, path);
}

/// 选择目标作品（返回 work id，kUnassignedWork 表示未归类）
Future<int?> showWorkPicker(BuildContext context, {String title = '移动到作品'}) {
  return showDialog<int>(
    context: context,
    builder: (ctx) {
      final works = ctx.read<AppState>().works;
      return AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 320,
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.folder_off_outlined),
                title: const Text('未归类'),
                onTap: () => Navigator.pop(ctx, kUnassignedWork),
              ),
              for (final w in works)
                ListTile(
                  leading: const Icon(Icons.album_outlined),
                  title: Text(w.name),
                  onTap: () => Navigator.pop(ctx, w.id),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// 标签选择对话框，返回选中的标签（含新建的）
Future<List<Tag>?> showTagPickerDialog(BuildContext context,
    {String title = '添加标签', Set<int>? selectedTagIds}) {
  return showDialog<List<Tag>>(
    context: context,
    builder: (_) => _TagPickerDialog(title: title, selectedTagIds: selectedTagIds),
  );
}

class _PromptDialog extends StatefulWidget {
  final String title;
  final String initial;
  final String hint;
  const _PromptDialog(
      {required this.title, this.initial = '', this.hint = ''});

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
        decoration: InputDecoration(hintText: widget.hint),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消')),
        TextButton(
            onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
            child: const Text('确定')),
      ],
    );
  }
}

class _TagPickerDialog extends StatefulWidget {
  final String title;
  final Set<int>? selectedTagIds;
  const _TagPickerDialog({required this.title, this.selectedTagIds});

  @override
  State<_TagPickerDialog> createState() => _TagPickerDialogState();
}

class _TagPickerDialogState extends State<_TagPickerDialog> {
  final _newCtrl = TextEditingController();
  final Set<int> _selected = {};

  @override
  void initState() {
    super.initState();
    _selected.addAll(widget.selectedTagIds ?? const {});
  }

  @override
  void dispose() {
    _newCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final tags = appState.allTags;

    // 按命名空间分组
    final groups = <String, List<Tag>>{};
    for (final t in tags) {
      groups.putIfAbsent(t.namespace, () => []).add(t);
    }

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        height: 420,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                children: [
                  for (final entry in groups.entries) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        entry.key,
                        style: TextStyle(
                            fontSize: 11,
                            color: AppColors.namespaceColor(entry.key)),
                      ),
                    ),
                    for (final t in entry.value)
                      CheckboxListTile(
                        dense: true,
                        secondary: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: AppColors.parseColor(t.color),
                            shape: BoxShape.circle,
                          ),
                        ),
                        value: _selected.contains(t.id),
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              _selected.add(t.id!);
                            } else {
                              _selected.remove(t.id);
                            }
                          });
                        },
                        title: Text(t.name, style: const TextStyle(fontSize: 13)),
                      ),
                  ],
                ],
              ),
            ),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newCtrl,
                    decoration: const InputDecoration(
                      hintText: '新建标签（命名空间:名称）',
                      isDense: true,
                    ),
                    onSubmitted: (_) => _createNew(appState),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add, color: AppColors.accent),
                  onPressed: () => _createNew(appState),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消')),
        TextButton(
          onPressed: () {
            final selected = tags.where((t) => _selected.contains(t.id)).toList();
            Navigator.pop(context, selected);
          },
          child: const Text('确定'),
        ),
      ],
    );
  }

  Future<void> _createNew(AppState appState) async {
    final raw = _newCtrl.text.trim();
    if (raw.isEmpty) return;
    String ns = 'general';
    String name = raw;
    final ci = raw.indexOf(':');
    if (ci > 0) {
      ns = raw.substring(0, ci);
      name = raw.substring(ci + 1);
    }
    final tag = await appState.createTag(name, namespace: ns);
    if (mounted) {
      setState(() {
        _selected.add(tag.id!);
        _newCtrl.clear();
      });
    }
  }
}
