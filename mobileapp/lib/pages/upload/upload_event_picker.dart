import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:mobileapp/core/network/dio_helper.dart';
import 'package:mobileapp/models/event_invitation_model.dart';

/// Selects an accessible event for the camera, or creates one in one step.
/// The parent validates that no live camera receiver is being reassigned.
Future<void> showUploadEventPicker({
  required BuildContext context,
  required EventSummary? activeEvent,
  required bool canCreate,
  required Future<bool> Function(EventSummary, bool) onSelect,
  required Future<bool> Function(String) onCreate,
  bool focusCreate = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _UploadEventPicker(
      activeEvent: activeEvent,
      canCreate: canCreate,
      onSelect: onSelect,
      onCreate: onCreate,
      focusCreate: focusCreate,
    ),
  );
}

class _UploadEventPicker extends StatefulWidget {
  const _UploadEventPicker({
    required this.activeEvent,
    required this.canCreate,
    required this.onSelect,
    required this.onCreate,
    this.focusCreate = false,
  });

  final EventSummary? activeEvent;
  final bool canCreate;
  final Future<bool> Function(EventSummary, bool) onSelect;
  final Future<bool> Function(String) onCreate;
  final bool focusCreate;

  @override
  State<_UploadEventPicker> createState() => _UploadEventPickerState();
}

class _UploadEventPickerState extends State<_UploadEventPicker> {
  final _search = TextEditingController();
  final _newTitle = TextEditingController();
  final _createFocus = FocusNode();
  final List<({EventSummary event, bool enabled})> _events = [];
  bool _loading = false;
  bool _working = false;
  bool _hasMore = true;
  int _page = 1;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMore();
    if (widget.focusCreate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _createFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _newTitle.dispose();
    _createFocus.dispose();
    super.dispose();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await DioHelper.get(
        '/event/my-events',
        queryParameters: {'page': _page, 'limit': 100},
      );
      final payload = response.data;
      final raw = payload is Map ? payload['data'] : null;
      final rows = raw is List ? raw : const [];
      final fresh = <({EventSummary event, bool enabled})>[];
      for (final item in rows) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final event = EventSummary.fromJson(map);
        if (event.id.isEmpty) continue;
        fresh.add((event: event, enabled: map['isActive'] != false));
      }
      if (!mounted) return;
      setState(() {
        final known = _events.map((item) => item.event.id).toSet();
        _events.addAll(fresh.where((item) => !known.contains(item.event.id)));
        _hasMore = payload is Map && payload['hasNextPage'] == true;
        _page += 1;
      });
    } on DioException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.response?.data is Map
              ? (error.response!.data as Map)['message']?.toString() ??
                    'Could not load events'
              : 'Could not load events',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load events');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _select(EventSummary event, bool enabled) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      final success = await widget.onSelect(event, enabled);
      if (success && mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _create() async {
    final title = _newTitle.text.trim();
    if (!widget.canCreate || title.isEmpty || _working) return;
    setState(() => _working = true);
    try {
      final success = await widget.onCreate(title);
      if (success && mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final matching = _events
        .where(
          (item) =>
              item.event.title.toLowerCase().contains(query) ||
              item.event.id.toLowerCase().contains(query),
        )
        .toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.78,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choose upload event',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                const Text(
                  'New photos go only to the selected event.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search events by name',
                    prefixIcon: const Icon(Icons.search_rounded),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      tooltip: 'Refresh events',
                      onPressed: _working
                          ? null
                          : () {
                              setState(() {
                                _events.clear();
                                _page = 1;
                                _hasMore = true;
                              });
                              _loadMore();
                            },
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ),
                ),
                if (widget.canCreate) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _newTitle,
                          focusNode: _createFocus,
                          onChanged: (_) => setState(() {}),
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _create(),
                          decoration: const InputDecoration(
                            hintText: 'New event name',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _working || _newTitle.text.trim().isEmpty
                            ? null
                            : _create,
                        icon: _working
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.add_rounded),
                        label: const Text('Create & use'),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    children: [
                      if (_error != null)
                        ListTile(
                          title: Text(_error!),
                          trailing: TextButton(
                            onPressed: _loadMore,
                            child: const Text('Retry'),
                          ),
                        ),
                      if (_loading && _events.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      if (!_loading && _events.isEmpty && _error == null)
                        const ListTile(
                          title: Text('No events found'),
                          subtitle: Text(
                            'Create a new event above or accept an invitation.',
                          ),
                        ),
                      ...matching.map((item) {
                        final active = item.event.id == widget.activeEvent?.id;
                        return ListTile(
                          leading: Icon(
                            active
                                ? Icons.check_circle_rounded
                                : Icons.event_available_outlined,
                            color: active
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                          title: Text(
                            item.event.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            active
                                ? 'Currently selected'
                                : item.enabled
                                ? 'Ready for uploads'
                                : 'Event inactive',
                          ),
                          trailing: active
                              ? const Text('Selected')
                              : const Icon(Icons.chevron_right_rounded),
                          enabled: !_working && !active,
                          onTap: () => _select(item.event, item.enabled),
                        );
                      }),
                      if (matching.isEmpty && _events.isNotEmpty)
                        const ListTile(title: Text('No matching events')),
                      if (_hasMore)
                        Center(
                          child: TextButton.icon(
                            onPressed: _loading || _working ? null : _loadMore,
                            icon: _loading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.expand_more_rounded),
                            label: const Text('Load more events'),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
