import 'package:flutter/material.dart';
import 'package:mobileapp/core/network/ai_settings_api.dart';
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
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    AiSettingsApi.changes.addListener(_settingsChanged);
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

  void _settingsChanged() {
    if (AiSettingsApi.changes.value == widget.eventId && !_saving) _load();
  }

  @override
  void dispose() {
    AiSettingsApi.changes.removeListener(_settingsChanged);
    super.dispose();
  }

  Future<void> _load() async {
    final eventId = widget.eventId;
    final albumId = widget.albumId;
    final generation = ++_loadGeneration;
    bool current() =>
        mounted &&
        generation == _loadGeneration &&
        widget.eventId == eventId &&
        widget.albumId == albumId;
    if (mounted) setState(() => _loading = true);
    try {
      final result = await AiSettingsApi.read(eventId, albumId);
      if (!current()) return;
      final enabled = AiSettingsApi.enabled(result.event, result.scope);
      setState(() {
        _enabled = enabled;
        _hasValue = true;
      });
      widget.onValueChanged?.call(enabled);
    } catch (_) {
      if (current()) setState(() => _hasValue = false);
    } finally {
      if (current()) setState(() => _loading = false);
    }
  }

  Future<void> _setEnabled(bool enabled) async {
    if (_loading || _saving || !_hasValue) return;
    final eventId = widget.eventId;
    final albumId = widget.albumId;
    bool current() =>
        mounted && widget.eventId == eventId && widget.albumId == albumId;
    setState(() => _saving = true);
    try {
      await AiSettingsApi.save(eventId, albumId, {
        'autoEnhanceImages': enabled,
      });
      if (!current()) return;
      await _load();
      if (current() && _hasValue) {
        AppToast.success(
          _enabled
              ? 'AI enhancement enabled for new photos'
              : 'AI enhancement disabled for new photos',
        );
      }
    } catch (_) {
      if (current()) AppToast.error('Could not save AI enhancement setting');
    } finally {
      if (current()) setState(() => _saving = false);
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
