import 'package:flutter/material.dart';
import 'package:mobileapp/core/network/dio_helper.dart';
import 'package:mobileapp/core/theme/app_theme.dart';
import 'package:mobileapp/utilities/app_toast.dart';

/// Uses the album override when a real album is selected, otherwise the event default.
class EventAutoEnhanceToggle extends StatefulWidget {
  const EventAutoEnhanceToggle({
    super.key,
    required this.eventId,
    this.albumId,
    this.onValueChanged,
  });

  final String eventId;
  final String? albumId;
  final ValueChanged<bool>? onValueChanged;

  @override
  State<EventAutoEnhanceToggle> createState() => _EventAutoEnhanceToggleState();
}

class _EventAutoEnhanceToggleState extends State<EventAutoEnhanceToggle> {
  bool _loading = true;
  bool _saving = false;
  bool _hasValue = false;
  bool _enabled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant EventAutoEnhanceToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eventId != widget.eventId ||
        oldWidget.albumId != widget.albumId) {
      _saving = false;
      _hasValue = false;
      _loading = true;
      _load();
    }
  }

  Future<void> _load() async {
    final eventId = widget.eventId;
    final albumId = widget.albumId;
    if (mounted) setState(() => _loading = true);
    try {
      final response = await DioHelper.get(
        '/event/get-one',
        queryParameters: {'id': eventId},
      );
      final raw = response.data is Map ? response.data['data'] : null;
      if (raw is! Map) throw StateError('Missing event settings');
      bool enabled = raw['autoEnhanceImages'] == true;
      if (albumId != null) {
        final response = await DioHelper.get(
          '/album/get-all',
          queryParameters: {'eventId': eventId},
        );
        final matches = (response.data['data'] as List).where(
          (row) =>
              row is Map && (row['_id'] ?? row['id']).toString() == albumId,
        );
        if (matches.isEmpty) throw StateError('Album not found');
        final album = matches.first as Map;
        if (album['autoEnhanceImages'] is bool) {
          enabled = album['autoEnhanceImages'] == true;
        }
      }
      if (!mounted || widget.eventId != eventId || widget.albumId != albumId) {
        return;
      }
      setState(() {
        _enabled = enabled;
        _hasValue = true;
      });
      widget.onValueChanged?.call(enabled);
    } catch (_) {
      if (mounted && widget.eventId == eventId && widget.albumId == albumId) {
        setState(() => _hasValue = false);
      }
    } finally {
      if (mounted && widget.eventId == eventId && widget.albumId == albumId) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _setEnabled(bool enabled) async {
    if (_loading || _saving || !_hasValue) return;
    final eventId = widget.eventId;
    final albumId = widget.albumId;
    setState(() => _saving = true);
    try {
      await DioHelper.patch(
        albumId == null ? '/event/update' : '/album/update',
        queryParameters: {'id': albumId ?? eventId},
        data: {'autoEnhanceImages': enabled},
      );
      if (!mounted || widget.eventId != eventId || widget.albumId != albumId) {
        return;
      }
      setState(() => _enabled = enabled);
      widget.onValueChanged?.call(enabled);
      AppToast.success(
        enabled
            ? 'AI enhancement enabled for new photos'
            : 'AI enhancement disabled for new photos',
      );
    } catch (_) {
      if (mounted && widget.eventId == eventId && widget.albumId == albumId) {
        AppToast.error('Could not save AI enhancement setting');
      }
    } finally {
      if (mounted && widget.eventId == eventId && widget.albumId == albumId) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Container(
                width: 37,
                height: 37,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 11),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI image enhancement',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'On: add AI-enhanced copies of new photos (uses credits). Off: originals only.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.mutedForeground,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              if (_loading || _saving)
                const Padding(
                  padding: EdgeInsets.all(13),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (!_hasValue)
                IconButton(
                  tooltip: 'Retry enhancement settings',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded),
                )
              else
                Switch(
                  key: const Key('event-auto-enhance-switch'),
                  value: _enabled,
                  onChanged: _setEnabled,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class EventImageEnhancementPage extends StatelessWidget {
  const EventImageEnhancementPage({
    super.key,
    required this.eventId,
    required this.eventTitle,
  });

  final String eventId;
  final String eventTitle;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('AI image enhancement')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
      children: [
        Text(
          eventTitle,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        const Text(
          'This applies to the entire event, including new camera and phone uploads.',
          style: TextStyle(fontSize: 12, color: AppColors.mutedForeground),
        ),
        const SizedBox(height: 16),
        EventAutoEnhanceToggle(eventId: eventId),
      ],
    ),
  );
}
