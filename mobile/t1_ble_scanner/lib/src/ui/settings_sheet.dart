import 'package:flutter/material.dart';

import '../models/app_config.dart';
import '../utils/beacon_utils.dart';

/// Bottom sheet with BLE scan configuration.
///
/// Uses the caller's [TextEditingController]s so that values survive sheet
/// open/close cycles without re-parsing.
class SettingsSheet extends StatefulWidget {
  const SettingsSheet({
    super.key,
    required this.keyController,
    required this.tagMaxController,
    required this.prodWindowController,
    required this.protoSlotMaxController,
    required this.initialMode,
    required this.config,
    required this.onModeChanged,
  });

  final TextEditingController keyController;
  final TextEditingController tagMaxController;
  final TextEditingController prodWindowController;
  final TextEditingController protoSlotMaxController;
  final T1ScanMode initialMode;
  final AppConfig? config;
  final ValueChanged<T1ScanMode> onModeChanged;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  late T1ScanMode _mode;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final local = config?.localOperator;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── drag handle ──────────────────────────────────────────────────
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),

          // ── title ────────────────────────────────────────────────────────
          Row(
            children: [
              const Icon(Icons.tune_rounded, size: 18, color: Colors.white70),
              const SizedBox(width: 8),
              Text(
                'Настройки сканирования',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── operator info chips ──────────────────────────────────────────
          if (local != null) ...[
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _chip('UUID', formatUuid(local.uuid), context),
                _chip('Код', local.code, context),
                _chip(
                  'Остановок',
                  '${config?.stops.length ?? 0}',
                  context,
                ),
              ],
            ),
            const SizedBox(height: 14),
          ],

          // ── key field ────────────────────────────────────────────────────
          TextField(
            controller: widget.keyController,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(fontFamily: 'monospace', letterSpacing: 1.2),
            decoration: InputDecoration(
              labelText: 'AES-128 KEY',
              helperText: '32 HEX-символа',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear, size: 18),
                tooltip: 'Очистить ключ',
                onPressed: () => widget.keyController.clear(),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── mode selector ────────────────────────────────────────────────
          DropdownButtonFormField<T1ScanMode>(
            initialValue: _mode,
            decoration: const InputDecoration(
              labelText: 'Режим T1',
              border: OutlineInputBorder(),
            ),
            items: T1ScanMode.values
                .map(
                  (m) => DropdownMenuItem(
                    value: m,
                    child: Text(m.label),
                  ),
                )
                .toList(growable: false),
            onChanged: (m) {
              if (m == null) return;
              setState(() => _mode = m);
              widget.onModeChanged(m);
            },
          ),
          const SizedBox(height: 12),

          // ── tagMax + slot range ──────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.tagMaxController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'TagID до',
                    helperText: 'напр. 100',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _mode == T1ScanMode.production
                      ? widget.prodWindowController
                      : widget.protoSlotMaxController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: _mode == T1ScanMode.production
                        ? 'Слоты ±'
                        : 'Слоты 0..',
                    helperText: _mode == T1ScanMode.production
                        ? 'напр. 5'
                        : 'напр. 10000',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),

          // ── hint ─────────────────────────────────────────────────────────
          const SizedBox(height: 10),
          Text(
            _mode == T1ScanMode.prototype
                ? 'Prototype: слот = uptime ÷ 10 с. '
                    'Таблица: (TagID+1) × (Слоты+1) записей.'
                : 'Production: слот = unix_time ÷ 300 с. '
                    'Таблица: (TagID+1) × (2×Слоты+1) записей.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.white38),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, String value, BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF1E3A5F),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Colors.blueAccent.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(fontSize: 11, color: Colors.white70),
      ),
    );
  }
}
