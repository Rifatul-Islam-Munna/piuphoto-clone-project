import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobileapp/core/upload/transfer_ledger_storage.dart';

/// Only query in-flight AI jobs while a transfer screen is visible. Shared
/// ledger updates keep the overview, camera grid and transfer history in sync.
class TransferAiMonitor extends StatefulWidget {
  const TransferAiMonitor({
    super.key,
    required this.eventId,
    this.enabled = true,
    required this.child,
  });
  final String eventId;
  final bool enabled;
  final Widget child;

  @override
  State<TransferAiMonitor> createState() => _TransferAiMonitorState();
}

class _TransferAiMonitorState extends State<TransferAiMonitor> {
  Timer? _timer;
  bool _running = false;
  bool get _needsRefresh =>
      widget.enabled &&
      TransferLedgerStorage.items.value.any(
        (item) =>
            item.eventId == widget.eventId &&
            item.isUploaded &&
            item.needsDeliveryRefresh &&
            item.eventImageId?.isNotEmpty == true,
      );

  @override
  void initState() {
    super.initState();
    TransferLedgerStorage.items.addListener(_schedule);
    _schedule();
  }

  @override
  void didUpdateWidget(covariant TransferAiMonitor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eventId != widget.eventId ||
        oldWidget.enabled != widget.enabled) {
      _timer?.cancel();
      _timer = null;
      _schedule();
    }
  }

  void _schedule() {
    if (!mounted) return;
    if (!_needsRefresh) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (_running || _timer?.isActive == true) return;
    _timer = Timer(const Duration(seconds: 5), () async {
      _timer = null;
      if (!mounted || !_needsRefresh) return;
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if ((lifecycle == null || lifecycle == AppLifecycleState.resumed) &&
          ModalRoute.of(context)?.isCurrent != false) {
        _running = true;
        try {
          await TransferLedgerStorage.refreshAiStatuses(widget.eventId);
        } finally {
          _running = false;
        }
      }
      _schedule();
    });
  }

  @override
  void dispose() {
    TransferLedgerStorage.items.removeListener(_schedule);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
