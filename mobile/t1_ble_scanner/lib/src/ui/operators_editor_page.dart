import 'package:flutter/material.dart';

import '../services/operators_repository.dart';
import '../utils/beacon_utils.dart';

/// Color palette for operators (ARGB values shown on the dark radar canvas).
const _kPalette = [
  0xFF40C4FF, // light blue (default)
  0xFFC084FC, // purple
  0xFFFF5252, // red
  0xFFFF6D00, // deep orange
  0xFFFFD600, // yellow
  0xFF69FF47, // lime
  0xFF00E5FF, // cyan
  0xFF651FFF, // violet
  0xFFFF4081, // pink
  0xFFFF8A65, // salmon
  0xFF80CBC4, // teal
  0xFFCE93D8, // lavender
];

/// Full-screen editor for UUID → operator mappings.
///
/// All operators are shown in a flat list — every entry can be edited or
/// deleted (including those pre-populated from app_config.json).
/// Each operator can have an individually chosen color that is used for its
/// dot on the radar.
class OperatorsEditorPage extends StatefulWidget {
  const OperatorsEditorPage({super.key, required this.repository});

  final OperatorsRepository repository;

  @override
  State<OperatorsEditorPage> createState() => _OperatorsEditorPageState();
}

class _OperatorsEditorPageState extends State<OperatorsEditorPage> {
  // ── dialogs ─────────────────────────────────────────────────────────────────

  Future<void> _showEditDialog({Operator? existing}) async {
    final uuidCtrl = TextEditingController(
      text: existing != null ? _fmtUuid(existing.uuid) : '',
    );
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final codeCtrl = TextEditingController(text: existing?.code ?? '');
    var selectedColor = existing?.colorValue ?? _kPalette.first;
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          title: Text(
            existing == null ? 'Добавить оператора' : 'Редактировать',
            style: const TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // UUID
                  TextFormField(
                    controller: uuidCtrl,
                    enabled: existing == null,
                    style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'monospace',
                        fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'UUID',
                      helperText: 'XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Введите UUID';
                      final n = normalizeUuid(v.trim());
                      if (n.length != 32) return 'Некорректный UUID (32 hex)';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  // Name
                  TextFormField(
                    controller: nameCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Название оператора',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Введите название' : null,
                  ),
                  const SizedBox(height: 14),
                  // Code
                  TextFormField(
                    controller: codeCtrl,
                    style: const TextStyle(color: Colors.white),
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Код оператора',
                      helperText: 'Короткий идентификатор, напр.: GORTR',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Введите код' : null,
                  ),
                  const SizedBox(height: 16),
                  // Color picker
                  const Text(
                    'Цвет на радаре',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _kPalette.map((argb) {
                      final selected = argb == selectedColor;
                      return GestureDetector(
                        onTap: () => setLocal(() => selectedColor = argb),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Color(argb),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected
                                  ? Colors.white
                                  : Colors.transparent,
                              width: 2.5,
                            ),
                            boxShadow: selected
                                ? [
                                    BoxShadow(
                                      color: Color(argb).withValues(alpha: 0.6),
                                      blurRadius: 8,
                                    )
                                  ]
                                : null,
                          ),
                          child: selected
                              ? const Icon(Icons.check,
                                  size: 16, color: Colors.black)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
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
      ),
    );

    if (confirmed == true && mounted) {
      final op = Operator(
        uuid: normalizeUuid(uuidCtrl.text.trim()),
        name: nameCtrl.text.trim(),
        code: codeCtrl.text.trim().toUpperCase(),
        colorValue: selectedColor,
      );
      await widget.repository.upsert(op);
      setState(() {});
    }

    uuidCtrl.dispose();
    nameCtrl.dispose();
    codeCtrl.dispose();
  }

  Future<void> _confirmDelete(Operator op) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text('Удалить оператора?',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'Метки оператора «${op.name}» (${op.code}) будут отображаться '
          'как обычные iBeacon.',
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
      await widget.repository.delete(op.uuid);
      setState(() {});
    }
  }

  // ── helpers ─────────────────────────────────────────────────────────────────

  String _fmtUuid(String normalized) {
    if (normalized.length != 32) return normalized;
    return ('${normalized.substring(0, 8)}-'
            '${normalized.substring(8, 12)}-'
            '${normalized.substring(12, 16)}-'
            '${normalized.substring(16, 20)}-'
            '${normalized.substring(20)}')
        .toUpperCase();
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ops = widget.repository.operators;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text('Операторы UUID'),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Chip(
              label: Text('${ops.length}'),
              backgroundColor: const Color(0xFF172554),
              labelStyle:
                  const TextStyle(color: Colors.white70, fontSize: 12),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
      body: ops.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.sensors_off_rounded,
                        size: 48, color: Colors.white24),
                    const SizedBox(height: 12),
                    const Text(
                      'Операторов нет.\nНажмите «Добавить» чтобы добавить\nоператора по UUID.',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(color: Colors.white38, fontSize: 14),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
              itemCount: ops.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (_, i) => _OperatorTile(
                op: ops[i],
                fmtUuid: _fmtUuid(ops[i].uuid),
                onEdit: () => _showEditDialog(existing: ops[i]),
                onDelete: () => _confirmDelete(ops[i]),
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditDialog(),
        icon: const Icon(Icons.add_circle_outline_rounded),
        label: const Text('Добавить'),
        backgroundColor: const Color(0xFF1D4ED8),
        foregroundColor: Colors.white,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _OperatorTile extends StatelessWidget {
  const _OperatorTile({
    required this.op,
    required this.fmtUuid,
    required this.onEdit,
    required this.onDelete,
  });

  final Operator op;
  final String fmtUuid;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final dotColor = Color(op.colorValue);

    return Material(
      color: const Color(0xFF172554),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Row(
            children: [
              // Color dot
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: dotColor.withValues(alpha: 0.5),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Name + code + UUID
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          op.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: dotColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            op.code,
                            style: TextStyle(
                              color: dotColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      fmtUuid,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
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
