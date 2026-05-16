import 'package:flutter/material.dart';

import '../models/app_config.dart';
import '../models/scanner_settings.dart';
import '../utils/beacon_utils.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    required this.config,
    required this.initialSettings,
    super.key,
  });

  final AppConfig config;
  final ScannerSettings initialSettings;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _keyController;
  late final TextEditingController _tagMaxController;
  late final TextEditingController _prodWindowController;
  late final TextEditingController _protoSlotMaxController;
  late T1ScanMode _scanMode;

  @override
  void initState() {
    super.initState();
    _keyController = TextEditingController(text: widget.initialSettings.keyHex);
    _tagMaxController = TextEditingController(
      text: widget.initialSettings.maxTagId.toString(),
    );
    _prodWindowController = TextEditingController(
      text: widget.initialSettings.productionSlotWindow.toString(),
    );
    _protoSlotMaxController = TextEditingController(
      text: widget.initialSettings.prototypeSlotMax.toString(),
    );
    _scanMode = widget.initialSettings.mode;
  }

  @override
  void dispose() {
    _keyController.dispose();
    _tagMaxController.dispose();
    _prodWindowController.dispose();
    _protoSlotMaxController.dispose();
    super.dispose();
  }

  void _restoreDefaults() {
    final defaults = widget.config.defaults;
    setState(() {
      _keyController.text = defaults.keyHex;
      _tagMaxController.text = defaults.tagMax.toString();
      _prodWindowController.text = defaults.productionSlotWindow.toString();
      _protoSlotMaxController.text = defaults.prototypeSlotMax.toString();
      _scanMode = T1ScanMode.production;
    });
  }

  void _save() {
    final settings = ScannerSettings(
      keyHex: _keyController.text.trim().toUpperCase(),
      mode: _scanMode,
      maxTagId: int.tryParse(_tagMaxController.text.trim()) ??
          widget.initialSettings.maxTagId,
      productionSlotWindow: int.tryParse(_prodWindowController.text.trim()) ??
          widget.initialSettings.productionSlotWindow,
      prototypeSlotMax: int.tryParse(_protoSlotMaxController.text.trim()) ??
          widget.initialSettings.prototypeSlotMax,
    );
    Navigator.of(context).pop(settings);
  }

  @override
  Widget build(BuildContext context) {
    final local = widget.config.localOperator;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
        actions: [
          IconButton(
            onPressed: _restoreDefaults,
            tooltip: 'Вернуть значения по умолчанию',
            icon: const Icon(Icons.restart_alt),
          ),
          IconButton(
            onPressed: _save,
            tooltip: 'Сохранить настройки',
            icon: const Icon(Icons.check),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Конфигурация приложения',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Все параметры хранятся локально. Интернет для распознавания T1 не используется.',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Colors.white70),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _InfoChip(
                            label: 'T1 UUID', value: formatUuid(local.uuid)),
                        _InfoChip(label: 'T1 код', value: local.code),
                        _InfoChip(
                            label: 'Остановок',
                            value: '${widget.config.stops.length}'),
                        _InfoChip(
                            label: 'Внешних UUID',
                            value: '${widget.config.externalOperators.length}'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Параметры дешифровки T1',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _keyController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'AES-128 KEY',
                        helperText:
                            'Ключ используется только для локальной дешифровки T1',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<T1ScanMode>(
                      initialValue: _scanMode,
                      decoration: const InputDecoration(
                        labelText: 'Режим слотов T1',
                      ),
                      items: T1ScanMode.values
                          .map(
                            (mode) => DropdownMenuItem<T1ScanMode>(
                              value: mode,
                              child: Text(mode.label),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (mode) {
                        if (mode == null) return;
                        setState(() => _scanMode = mode);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _tagMaxController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'TagID до',
                        helperText:
                            'Верхняя граница диапазона TagID для локального подбора',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _prodWindowController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Production: слоты ±',
                        helperText:
                            'Окно поиска относительно текущего Unix slot',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _protoSlotMaxController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Prototype: слоты 0..N',
                        helperText:
                            'Максимальный слот при работе в prototype-режиме',
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Сохранить настройки'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF172554),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.4)),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: Colors.white70),
            ),
            TextSpan(
              text: value,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
