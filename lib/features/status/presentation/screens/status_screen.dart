import 'package:flutter/material.dart';
import 'package:hoopix/core/theme/hoopix_metrics.dart';
import 'package:hoopix/core/theme/hoopix_theme.dart';
import 'package:hoopix/core/theme/hoopix_typography.dart';
import 'package:hoopix/core/widgets/tabular_text.dart';
import 'package:hoopix/features/status/data/repositories/status_repository_impl.dart';
import 'package:hoopix/features/status/domain/entities/system_snapshot.dart';
import 'package:hoopix/features/status/domain/repositories/status_repository.dart';
import 'package:hoopix/features/status/domain/usecases/watch_system_status.dart';
import 'package:hoopix/features/status/presentation/state/status_controller.dart';
import 'package:hoopix/features/status/presentation/widgets/battery_card.dart';
import 'package:hoopix/features/status/presentation/widgets/cpu_gauge.dart';
import 'package:hoopix/features/status/presentation/widgets/disk_list.dart';
import 'package:hoopix/features/status/presentation/widgets/host_summary.dart';
import 'package:hoopix/features/status/presentation/widgets/memory_gauge.dart';
import 'package:hoopix/features/status/presentation/widgets/network_card.dart';

/// Live, read-only system-health dashboard. [repository] is injectable so
/// tests can substitute a fake instead of the real local one.
class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key, this.repository});

  final StatusRepository? repository;

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  late final StatusController _controller;

  @override
  void initState() {
    super.initState();
    final repository = widget.repository ?? StatusRepositoryImpl();
    _controller = StatusController(WatchSystemStatus(repository))..start();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final snapshot = _controller.snapshot;
        if (snapshot == null) {
          return _FirstLoad(error: _controller.error);
        }
        return _Dashboard(snapshot: snapshot);
      },
    );
  }
}

class _FirstLoad extends StatelessWidget {
  const _FirstLoad({this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    if (error != null) {
      return Center(
        child: Text(
          'Status unavailable: $error',
          style: HoopixType.body.copyWith(color: palette.labelSecondary),
        ),
      );
    }

    return Center(
      child: SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: palette.brand),
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.snapshot});

  final SystemSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        HoopixSpacing.xxxl,
        HoopixLayout.trafficLightInset,
        HoopixSpacing.xxxl,
        HoopixSpacing.xxxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(snapshot: snapshot),
          const SizedBox(height: HoopixSpacing.xxl),
          _CardRow(
            left: CpuGauge(cpu: snapshot.cpu),
            right: MemoryGauge(memory: snapshot.memory),
          ),
          const SizedBox(height: HoopixSpacing.lg),
          _CardRow(
            left: BatteryCard(battery: snapshot.battery),
            right: NetworkCard(network: snapshot.network),
          ),
          const SizedBox(height: HoopixSpacing.lg),
          DiskList(disks: snapshot.disks),
        ],
      ),
    );
  }
}

/// Two equal-width cards that stay aligned at the top regardless of which
/// one is taller.
class _CardRow extends StatelessWidget {
  const _CardRow({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: left),
          const SizedBox(width: HoopixSpacing.lg),
          Expanded(child: right),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.snapshot});

  final SystemSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Status',
                style: HoopixType.largeTitle.copyWith(
                  color: palette.labelPrimary,
                ),
              ),
              const SizedBox(height: HoopixSpacing.xs),
              HostSummary(host: snapshot.host),
            ],
          ),
        ),
        const SizedBox(width: HoopixSpacing.lg),
        _LivePill(collectedAt: snapshot.collectedAt),
      ],
    );
  }
}

/// Small "this is updating" affordance. A live dashboard that never
/// acknowledges its own refresh looks frozen when values happen to be steady.
class _LivePill extends StatelessWidget {
  const _LivePill({required this.collectedAt});

  final DateTime collectedAt;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final time = TimeOfDay.fromDateTime(collectedAt);
    final stamp =
        '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: HoopixSpacing.md,
        vertical: HoopixSpacing.xs + 2,
      ),
      decoration: BoxDecoration(
        color: palette.surfaceSubtle,
        borderRadius: BorderRadius.circular(HoopixRadius.pill),
        border: Border.all(color: palette.separator),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: palette.success,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: HoopixSpacing.sm),
          TabularText(
            'Live · $stamp',
            style: HoopixType.numericCaption.copyWith(
              color: palette.labelSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
