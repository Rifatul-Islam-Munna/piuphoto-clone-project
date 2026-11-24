import 'package:flutter/material.dart';
import 'package:mobileapp/core/network/ai_settings_api.dart';
import 'package:mobileapp/core/theme/app_theme.dart';
import 'package:mobileapp/utilities/app_toast.dart';
import 'package:mobileapp/pages/event_gallery/album_retouch_controls.dart';

class AlbumAiSettingsPage extends StatefulWidget {
  const AlbumAiSettingsPage({
    super.key,
    required this.eventId,
    this.albumId,
    required this.albumTitle,
  });

  final String eventId;
  final String? albumId;
  final String albumTitle;

  @override
  State<AlbumAiSettingsPage> createState() => _AlbumAiSettingsPageState();
}

class _AlbumAiSettingsPageState extends State<AlbumAiSettingsPage> {
  static const presets = <String, (String, IconData, String)>{
    'auto': (
      'Auto',
      Icons.auto_awesome_rounded,
      'Automatically correct exposure, color and clarity for each photo.',
    ),
    'summit': (
      'Summit',
      Icons.groups_outlined,
      'Balanced indoor light, window highlights and natural faces.',
    ),
    'expo': (
      'Expo',
      Icons.storefront_outlined,
      'Correct mixed exhibition lighting, signage and product colors.',
    ),
    'ceremony': (
      'Ceremony',
      Icons.celebration_outlined,
      'Elegant natural colors, bright clothing and soft shadows.',
    ),
    'banquet': (
      'Banquet',
      Icons.restaurant_outlined,
      'Warm indoor light, noise reduction and realistic colors.',
    ),
    'sports': (
      'Sports',
      Icons.directions_run_rounded,
      'Recover useful action detail and reduce haze and noise.',
    ),
    'portrait': (
      'Portrait',
      Icons.face_retouching_natural,
      'Natural skin and balanced facial lighting without reshaping.',
    ),
    'low_light': (
      'Low light',
      Icons.nightlight_outlined,
      'Lift dark shadows and control noise without artificial detail.',
    ),
    'outdoor': (
      'Outdoor',
      Icons.wb_sunny_outlined,
      'Recover sky highlights and balance sunlight and shadows.',
    ),
  };

  final _notes = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool _enabled = false;
  bool _inherit = false;
  bool _eventEnabled = false;
  String _eventPreset = 'auto';
  String _eventPrompt = '';
  String _eventMode = 'both';
  String _preset = 'auto';
  String _mode = 'both';
  RetouchValues _eventAdjustments = retouchValues('auto');
  RetouchValues _adjustments = retouchValues('auto');

  bool get _isAlbum => widget.albumId != null;
  bool get _canEdit => !_loading && !_saving && !_inherit;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await AiSettingsApi.read(widget.eventId, widget.albumId);
      final event = result.event;
      final settings = result.scope;
      if (!mounted) return;
      setState(() {
        _eventEnabled = event['autoEnhanceImages'] == true;
        _eventPreset = presets.containsKey(event['aiPreset'])
            ? event['aiPreset'] as String
            : 'auto';
        _eventPrompt = event['aiPrompt']?.toString() ?? '';
        _eventAdjustments = retouchValues(_eventPreset, event['aiAdjustments']);
        _eventMode = event['aiGalleryMode'] == 'enhanced_only'
            ? 'enhanced_only'
            : 'both';
        _inherit =
            _isAlbum &&
            [
              'autoEnhanceImages',
              'aiPreset',
              'aiPrompt',
              'aiAdjustments',
              'aiGalleryMode',
            ].every((key) => settings[key] == null);
        _enabled = (settings['autoEnhanceImages'] ?? _eventEnabled) == true;
        final preset = settings['aiPreset'] ?? _eventPreset;
        _preset = presets.containsKey(preset) ? preset as String : 'auto';
        _notes.text = (settings['aiPrompt'] ?? _eventPrompt).toString();
        _adjustments = retouchValues(
          _preset,
          settings['aiAdjustments'] ??
              (_preset == _eventPreset ? _eventAdjustments : null),
        );
        _mode = (settings['aiGalleryMode'] ?? _eventMode) == 'enhanced_only'
            ? 'enhanced_only'
            : 'both';
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load AI settings.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setInherit(bool value) {
    setState(() {
      _inherit = value;
      if (value) {
        _enabled = _eventEnabled;
        _preset = _eventPreset;
        _mode = _eventMode;
        _notes.text = _eventPrompt;
        _adjustments = retouchValues(_eventPreset, _eventAdjustments);
      }
    });
  }

  Future<void> _save() async {
    if (_saving || _loading || _error != null) return;
    setState(() => _saving = true);
    try {
      await AiSettingsApi.save(widget.eventId, widget.albumId, {
        'autoEnhanceImages': _inherit ? null : _enabled,
        'aiPreset': _inherit ? null : _preset,
        'aiPrompt': _inherit ? null : _notes.text.trim(),
        'aiAdjustments': _inherit ? null : _adjustments,
        'aiGalleryMode': _inherit ? null : _mode,
      });
      if (!mounted) return;
      AppToast.success('AI settings saved');
      Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) AppToast.error('Could not save AI settings. Try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 10),
    child: Text(
      text,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
    ),
  );

  Widget _card(Widget child) => Material(
    color: AppColors.card,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: AppColors.border),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: const EdgeInsets.all(14), child: child),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Retouch settings')),
      bottomNavigationBar: _loading || _error != null
          ? null
          : SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: SizedBox(
                height: 50,
                child: FilledButton(
                  key: const Key('save-album-ai-settings'),
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving...' : 'Save settings'),
                ),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!),
                  TextButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Text(
                  widget.albumTitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.mutedForeground,
                  ),
                ),
                if (_isAlbum) ...[
                  _heading('Apply to this album'),
                  _card(
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Use event defaults',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: const Text(
                        'Turn off to customize this album only.',
                        style: TextStyle(fontSize: 11),
                      ),
                      value: _inherit,
                      onChanged: _saving ? null : _setInherit,
                    ),
                  ),
                ],
                _heading('Automatic enhancement'),
                _card(
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'AI image enhancement',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    subtitle: const Text(
                      'Enhance new photos in the background. Uses AI credits.',
                      style: TextStyle(fontSize: 11),
                    ),
                    value: _enabled,
                    onChanged: _canEdit
                        ? (value) => setState(() {
                            _enabled = value;
                          })
                        : null,
                  ),
                ),
                _heading('Retouch preset'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: presets.entries
                      .map(
                        (entry) => ChoiceChip(
                          key: ValueKey('ai-preset-${entry.key}'),
                          avatar: Icon(entry.value.$2, size: 16),
                          label: Text(entry.value.$1),
                          selected: _preset == entry.key,
                          onSelected: _canEdit
                              ? (_) => setState(() {
                                  if (_preset != entry.key) {
                                    _preset = entry.key;
                                    _adjustments = retouchValues(_preset);
                                  }
                                })
                              : null,
                          showCheckmark: false,
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 10),
                _card(
                  Text(
                    presets[_preset]!.$3,
                    style: const TextStyle(fontSize: 12, height: 1.4),
                  ),
                ),
                const SizedBox(height: 10),
                AlbumRetouchControls(
                  preset: _preset,
                  values: _adjustments,
                  enabled: _canEdit,
                  onChanged: (values) => setState(() => _adjustments = values),
                ),
                _heading('Custom instructions'),
                TextField(
                  key: const Key('album-ai-prompt'),
                  controller: _notes,
                  enabled: _canEdit,
                  maxLength: 1000,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText:
                        'Example: Lift dark shadows, recover highlights, keep skin natural.',
                  ),
                ),
                const SizedBox(height: 6),
                _card(
                  const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.verified_user_outlined,
                        size: 20,
                        color: AppColors.primary,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Identity-first retouching is always on. Facial reshaping and age changes are never requested. AI corrects light and recoverable detail; severe blur cannot reliably be restored.',
                          style: TextStyle(fontSize: 12, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
                _heading('Gallery display'),
                _card(
                  Column(
                    children: [
                      for (final entry in const [
                        (
                          'both',
                          'Show both',
                          'Original and AI-enhanced photos',
                        ),
                        (
                          'enhanced_only',
                          'Enhanced only',
                          'Hide originals; show completed AI photos',
                        ),
                      ])
                        ListTile(
                          key: ValueKey('ai-gallery-${entry.$1}'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(
                            entry.$2,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: Text(
                            entry.$3,
                            style: const TextStyle(fontSize: 11),
                          ),
                          enabled: _canEdit,
                          leading: Icon(
                            _mode == entry.$1
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            color: _mode == entry.$1
                                ? AppColors.primary
                                : AppColors.mutedForeground,
                          ),
                          onTap: _canEdit
                              ? () => setState(() => _mode = entry.$1)
                              : null,
                        ),
                      if (!_enabled && _mode == 'enhanced_only')
                        const Text(
                          'New uploads will stay hidden from guests until enhanced. Enable AI to process new photos.',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.primary,
                          ),
                        ),
                      const Divider(height: 14),
                      const Text(
                        'Originals remain available to the photographer. Existing privacy and manual publication rules still apply. Videos are unaffected.',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.mutedForeground,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Preset changes apply to new enhancements and retries. Changing display does not reprocess or delete any photo.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.mutedForeground,
                    height: 1.4,
                  ),
                ),
              ],
            ),
    );
  }
}
