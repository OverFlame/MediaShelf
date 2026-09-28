import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/tag_dao.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/color_util.dart';

/// 打开多选标签对话框；返回选中的标签列表（null 表示取消）。
///
/// [filterTagIds] 非空时，仅显示这些 id 对应的标签（用于「移除标签」时只列
/// 出已存在的标签）。
///
/// [selectedTagIds] 非空时，这些标签在打开时就是勾选状态（用于编辑单个媒体
/// 已有标签的情形）。
Future<List<Tag>?> showTagPickerDialog(
  BuildContext context, {
  String title = '选择标签',
  Set<int>? filterTagIds,
  Set<int>? selectedTagIds,
}) {
  return showDialog<List<Tag>>(
    context: context,
    builder: (_) => _TagPickerDialog(
      title: title,
      filterTagIds: filterTagIds,
      selectedTagIds: selectedTagIds,
    ),
  );
}

class _TagPickerDialog extends StatefulWidget {
  final String title;
  final Set<int>? filterTagIds;
  final Set<int>? selectedTagIds;
  const _TagPickerDialog({
    required this.title,
    this.filterTagIds,
    this.selectedTagIds,
  });

  @override
  State<_TagPickerDialog> createState() => _TagPickerDialogState();
}

class _TagPickerDialogState extends State<_TagPickerDialog> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  final Set<int> _selected = {};

  @override
  void initState() {
    super.initState();
    if (widget.selectedTagIds != null) _selected.addAll(widget.selectedTagIds!);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final q = _search.toLowerCase();
    final tags = appState.allTags
        .where((t) => !t.isRule)
        .where((t) =>
            q.isEmpty ||
            t.name.toLowerCase().contains(q) ||
            t.namespace.toLowerCase().contains(q))
        .where((t) =>
            widget.filterTagIds == null || widget.filterTagIds!.contains(t.id))
        .toList();

    return AlertDialog(
      backgroundColor: AppColors.panel,
      title: Text(widget.title,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 16)),
      content: SizedBox(
        width: 320,
        height: 400,
        child: Column(
          children: [
            TextField(
              controller: _searchCtrl,
              autofocus: true,
              onChanged: (v) => setState(() => _search = v),
              style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
              decoration: const InputDecoration(
                hintText: '搜索标签...',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              // builder 只为可见行建 widget：一次性 toList 会为每个标签都建
              // CheckboxListTile，标签多时打开对话框就卡。
              child: ListView.builder(
                itemCount: tags.length,
                itemBuilder: (ctx, i) {
                  final t = tags[i];
                  final label = t.namespace.isEmpty || t.namespace == 'general'
                      ? t.name
                      : '${t.namespace}:${t.name}';
                  return CheckboxListTile(
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _selected.contains(t.id),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _selected.add(t.id!);
                      } else {
                        _selected.remove(t.id);
                      }
                    }),
                    title: Text(label,
                        style: const TextStyle(fontSize: 12)),
                    secondary: _dot(t.color),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消', style: TextStyle(color: AppColors.mutedLight)),
        ),
        FilledButton(
          onPressed: () {
            final selected =
                appState.allTags.where((t) => _selected.contains(t.id)).toList();
            Navigator.pop(context, selected);
          },
          child: const Text('确定'),
        ),
      ],
    );
  }

  Widget _dot(String hex) {
    final color = _parseColor(hex);
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Color _parseColor(String hex) =>
      parseHexColor(hex, fallback: AppColors.accent);
}
