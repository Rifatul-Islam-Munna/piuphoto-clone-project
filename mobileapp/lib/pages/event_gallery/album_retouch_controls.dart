import 'package:flutter/material.dart';
import 'package:mobileapp/core/theme/app_theme.dart';

typedef RetouchValues = Map<String, Map<String, int>>;
typedef RetouchControl = ({String label, int initial, int max, String key});

const photoControls = <RetouchControl>[
  (key: 'exposure', label: 'Exposure correction', initial: 85, max: 100),
  (key: 'highlights', label: 'Highlight recovery', initial: 85, max: 100),
  (key: 'shadows', label: 'Shadow recovery', initial: 80, max: 100),
  (key: 'whiteBalance', label: 'White balance', initial: 90, max: 100),
  (key: 'contrast', label: 'Contrast & depth', initial: 65, max: 100),
  (key: 'color', label: 'Natural color', initial: 60, max: 100),
  (key: 'noise', label: 'Noise reduction', initial: 65, max: 100),
  (key: 'sharpness', label: 'Sharpness & clarity', initial: 65, max: 100),
  (key: 'deblur', label: 'Blur correction', initial: 55, max: 100),
  (key: 'haze', label: 'Haze & glare reduction', initial: 40, max: 100),
];

const adultControls = <RetouchControl>[
  (key: 'blemish', label: 'Face blemish removal', initial: 20, max: 40),
  (key: 'forehead', label: 'Forehead wrinkle softening', initial: 8, max: 25),
  (key: 'eyeWrinkle', label: 'Eye wrinkle softening', initial: 8, max: 25),
  (key: 'underEye', label: 'Under-eye shadow correction', initial: 12, max: 30),
  (key: 'texture', label: 'Natural skin texture', initial: 8, max: 20),
];
const childControls = <RetouchControl>[
  (key: 'blemish', label: 'Temporary blemish correction', initial: 0, max: 15),
];

const _presetPhotoOverrides = <String, Map<String, int>>{
  'summit': {'highlights': 95, 'whiteBalance': 95, 'shadows': 85, 'color': 45},
  'expo': {'highlights': 95, 'whiteBalance': 95, 'color': 50, 'sharpness': 75},
  'ceremony': {'highlights': 95, 'shadows': 75, 'color': 65},
  'banquet': {'whiteBalance': 95, 'shadows': 85, 'noise': 85},
  'sports': {'sharpness': 85, 'deblur': 90, 'noise': 75, 'haze': 60},
  'portrait': {'contrast': 50, 'color': 50, 'sharpness': 50, 'deblur': 40},
  'low_light': {
    'exposure': 95,
    'shadows': 95,
    'noise': 95,
    'whiteBalance': 95,
    'sharpness': 55,
  },
  'outdoor': {'highlights': 95, 'shadows': 90, 'haze': 75, 'color': 65},
};

RetouchValues retouchValues(String preset, [Object? raw]) {
  Map<String, int> group(String name, List<RetouchControl> controls) {
    final custom = raw is Map ? raw[name] : null;
    return {
      for (final control in controls)
        control.key: custom is Map && custom[control.key] is num
            ? (custom[control.key] as num).round().clamp(0, control.max).toInt()
            : (name == 'photo'
                      ? (_presetPhotoOverrides[preset] ??
                            const <String, int>{})[control.key]
                      : null) ??
                  control.initial,
    };
  }

  return {
    'photo': group('photo', photoControls),
    'male': group('male', adultControls),
    'female': group('female', adultControls),
    'child': group('child', childControls),
  };
}

/// Adaptive model strengths, not pixel-level filters.
class AlbumRetouchControls extends StatefulWidget {
  const AlbumRetouchControls({
    super.key,
    required this.preset,
    required this.values,
    required this.enabled,
    required this.onChanged,
  });
  final String preset;
  final RetouchValues values;
  final bool enabled;
  final ValueChanged<RetouchValues> onChanged;

  @override
  State<AlbumRetouchControls> createState() => _AlbumRetouchControlsState();
}

class _AlbumRetouchControlsState extends State<AlbumRetouchControls> {
  bool _expanded = false;
  String _section = 'portrait';
  String _subject = 'female';

  void _change(String group, String key, int value) {
    final next = retouchValues(widget.preset, widget.values);
    next[group]![key] = value;
    widget.onChanged(next);
  }

  Widget _slider(String group, RetouchControl control) {
    final value = widget.values[group]?[control.key] ?? control.initial;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  control.label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                value == 0 ? 'Off' : '$value%',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            ),
            child: Slider(
              key: ValueKey('retouch-$group-${control.key}'),
              value: value.toDouble(),
              max: control.max.toDouble(),
              divisions: control.max,
              label: '$value%',
              onChanged: widget.enabled
                  ? (v) => _change(group, control.key, v.round())
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final group = _section == 'photo' ? 'photo' : _subject;
    final controls = group == 'photo'
        ? photoControls
        : group == 'child'
        ? childControls
        : adultControls;
    return Material(
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            key: const Key('retouch-preset-details'),
            leading: const Icon(
              Icons.tune_rounded,
              color: AppColors.primary,
              size: 21,
            ),
            title: const Text(
              'Preset details',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
            subtitle: const Text(
              'Portrait, lighting, color & detail',
              style: TextStyle(fontSize: 11),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _expanded ? 'Collapse' : 'Adjust',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 19,
                  color: AppColors.primary,
                ),
              ],
            ),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'portrait',
                        label: Text('Portrait'),
                        icon: Icon(Icons.face_outlined, size: 17),
                      ),
                      ButtonSegment(
                        value: 'photo',
                        label: Text('Photo correction'),
                        icon: Icon(Icons.photo_outlined, size: 17),
                      ),
                    ],
                    selected: {_section},
                    showSelectedIcon: false,
                    onSelectionChanged: (selected) =>
                        setState(() => _section = selected.first),
                  ),
                  const SizedBox(height: 15),
                  if (_section == 'portrait') ...[
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'male', label: Text('Male')),
                        ButtonSegment(value: 'female', label: Text('Female')),
                        ButtonSegment(value: 'child', label: Text('Child')),
                      ],
                      selected: {_subject},
                      showSelectedIcon: false,
                      onSelectionChanged: (selected) =>
                          setState(() => _subject = selected.first),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _subject == 'child'
                          ? 'Only minimal temporary blemish cleanup. No beauty or age-changing edits.'
                          : 'Natural portrait corrections only. Face shape, age, expression and permanent features are protected.',
                      style: const TextStyle(
                        color: AppColors.mutedForeground,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ] else
                    const Text(
                      'Adaptive strengths: the AI corrects actual defects, not a fixed filter. 0% turns off a correction. Unrecoverable detail is not invented.',
                      style: TextStyle(
                        color: AppColors.mutedForeground,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  const SizedBox(height: 16),
                  for (final control in controls) _slider(group, control),
                  const Divider(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: widget.enabled
                          ? () => widget.onChanged(retouchValues(widget.preset))
                          : null,
                      icon: const Icon(Icons.restart_alt_rounded, size: 17),
                      label: const Text('Reset preset details'),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
