import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/stops_repository.dart';

/// Full-screen editable directory of T1 stop names.
///
/// All entries look identical — there is no default/custom distinction.
/// Every entry can be edited or deleted.
class StopsEditorPage extends StatefulWidget {
  const StopsEditorPage({super.key, required this.repository});

  final StopsRepository repository;

  @override
  State<StopsEditorPage> createState() => _StopsEditorPageState();
}

class _StopsEditorPageState extends State<StopsEditorPage> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(
      () => setState(() => _query = _searchCtrl.text.trim().toLowerCase()),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── helpers ─────────────────────────────────────────────────────────────────

  List<MapEntry<int, String>> _filtered(Map<int, String> all) {
    if (_query.isEmpty) return all.entries.toList();
    return all.entries
        .where((e) =>
            '${e.key}'.contains(_query) ||
            e.value.toLowerCase().contains(_query))
        .toList();
  }

  // ── dialogs ─────────────────────────────────────────────────────────────────

  Future<void> _showEditDialog({int? existingTagId}) async {
    final tagIdCtrl = TextEditingController(
      text: existingTagId != null ? '$existingTagId' : '',
    );
    final nameCtrl = TextEditingController(
      text:
          existingTagId != null ? (widget.repository.getName(existingTagId) ?? '') : '',
    );
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        title: Text(
          existingTagId == null ? 'Добавить остановку' : 'Редактировать',
          style: const TextStyle(color: Colors.white),
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: tagIdCtrl,
                enabled: existingTagId == null,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'TagID (номер метки)',
                  helperText: 'Целое число ≥ 0',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Введите TagID';
                  final id = int.tryParse(v);
                  if (id == null || id < 0) return 'Некорректный TagID';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: nameCtrl,
                autofocus: existingTagId != null,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Название остановки',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Введите название' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.of(ctx).pop(true);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final tagId = int.parse(tagIdCtrl.text);
      await widget.repository.upsert(tagId, nameCtrl.text);
      setState(() {});
    }

    tagIdCtrl.dispose();
    nameCtrl.dispose();
  }

  Future<void> _confirmDelete(int tagId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text('Удалить остановку?',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'Запись «$name» (TagID $tagId) будет удалена.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await widget.repository.delete(tagId);
      setState(() {});
    }
  }

  // ── build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final all = widget.repository.all;
    final entries = _filtered(all);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text('Справочник остановок'),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Chip(
              label: Text('${all.length}'),
              backgroundColor: const Color(0xFF172554),
              labelStyle:
                  const TextStyle(color: Colors.white70, fontSize: 12),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── search bar ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Поиск по TagID или названию…',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon:
                    const Icon(Icons.search, color: Colors.white38),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white38),
                        onPressed: () => _searchCtrl.clear(),
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF172554),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),

          // ── list ────────────────────────────────────────────────────────────
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.location_off_rounded,
                            size: 48, color: Colors.white24),
                        const SizedBox(height: 12),
                        Text(
                          _query.isEmpty
                              ? 'Справочник пуст.\nНажмите + чтобы добавить остановку.'
                              : 'Ничего не найдено.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 14),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (_, i) => _StopTile(
                      tagId: entries[i].key,
                      name: entries[i].value,
                      onEdit: () =>
                          _showEditDialog(existingTagId: entries[i].key),
                      onDelete: () =>
                          _confirmDelete(entries[i].key, entries[i].value),
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditDialog(),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Добавить'),
        backgroundColor: const Color(0xFF1D4ED8),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _StopTile extends StatelessWidget {
  const _StopTile({
    required this.tagId,
    required this.name,
    required this.onEdit,
    required this.onDelete,
  });

  final int tagId;
  final String name;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF172554),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // TagID badge
              Container(
                width: 56,
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.2)),
                ),
                child: Text(
                  '#$tagId',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Stop name
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
              // Edit
              IconButton(
                icon: const Icon(Icons.edit_outlined,
                    size: 18, color: Colors.white38),
                tooltip: 'Редактировать',
                onPressed: onEdit,
                visualDensity: VisualDensity.compact,
              ),
              // Delete
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: Colors.redAccent),
                tooltip: 'Удалить',
                onPressed: onDelete,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
