import 'package:flutter/material.dart';

import '../models/beacon_view_model.dart';

/// Panel that lists every resolved T1 tag, sorted by signal strength.
class TagIdPanel extends StatelessWidget {
  const TagIdPanel({super.key, required this.devices});

  final List<BeaconViewModel> devices;

  @override
  Widget build(BuildContext context) {
    final resolved = devices.where((d) => d.isResolved).toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));

    if (resolved.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_off_rounded,
                  color: Colors.white24, size: 32),
              const SizedBox(height: 8),
              Text(
                'Нет расшифрованных T1-меток',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.white38),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── header ──────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              const Icon(Icons.location_on_rounded,
                  color: Colors.greenAccent, size: 16),
              const SizedBox(width: 6),
              Text(
                'Расшифрованные T1 · ${resolved.length}',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.greenAccent,
                      letterSpacing: 0.3,
                    ),
              ),
            ],
          ),
        ),
        // ── cards ────────────────────────────────────────────────────────────
        ...resolved.map((d) => _TagCard(device: d)),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _TagCard extends StatelessWidget {
  const _TagCard({required this.device});

  final BeaconViewModel device;

  @override
  Widget build(BuildContext context) {
    final data = device.resolvedData!;

    // Age since last packet
    final ageSec = DateTime.now().difference(device.lastSeen).inSeconds;
    final ageLabel = ageSec < 60
        ? '${ageSec}s ago'
        : '${ageSec ~/ 60}m ago';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0D2137),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.greenAccent.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── accent bar ──────────────────────────────────────────────────
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: Colors.greenAccent.withValues(alpha: 0.7),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  bottomLeft: Radius.circular(14),
                ),
              ),
            ),
            // ── tag-id badge ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: _TagBadge(tagId: data.tagId),
            ),
            // ── info ─────────────────────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      data.stopName ?? 'Не найдено в справочнике',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: data.stopName != null
                                ? Colors.white
                                : Colors.white54,
                            fontWeight: FontWeight.w600,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(
                          'Слот ${data.slot}',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.white38),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          ageLabel,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.white24),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // ── RSSI indicator ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 10, 14, 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _SignalBars(rssi: device.rssi),
                  const SizedBox(height: 4),
                  Text(
                    '${device.rssi} dBm',
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _TagBadge extends StatelessWidget {
  const _TagBadge({required this.tagId});

  final int tagId;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.greenAccent.withValues(alpha: 0.08),
        border: Border.all(
          color: Colors.greenAccent.withValues(alpha: 0.5),
          width: 1.2,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '#$tagId',
            style: const TextStyle(
              color: Colors.greenAccent,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              height: 1.1,
            ),
          ),
          Text(
            'TAG',
            style: TextStyle(
              color: Colors.greenAccent.withValues(alpha: 0.5),
              fontSize: 7,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _SignalBars extends StatelessWidget {
  const _SignalBars({required this.rssi});

  final int rssi;

  @override
  Widget build(BuildContext context) {
    // Map [-100, -30] → [0, 4] bars
    final bars = ((rssi.clamp(-100, -30) + 100) / 70.0 * 4).round().clamp(0, 4);
    final barColor = bars >= 3
        ? Colors.greenAccent
        : bars == 2
            ? Colors.amber
            : Colors.redAccent;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: List.generate(4, (i) {
        final active = i < bars;
        return Container(
          width: 5,
          height: 6.0 + i * 4,
          margin: const EdgeInsets.only(left: 2),
          decoration: BoxDecoration(
            color: active ? barColor : Colors.white12,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}
