import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:mobileapp/core/network/dio_helper.dart';
import 'package:mobileapp/core/network/mutation_wrapper.dart';
import 'package:mobileapp/core/storage/active_event_storage.dart';
import 'package:mobileapp/core/theme/app_theme.dart';
import 'package:mobileapp/models/event_invitation_model.dart';
import 'package:mobileapp/utilities/app_toast.dart';
import 'package:mobileapp/widgets/app_ui.dart';

@RoutePage()
class InvitationsPage extends StatefulWidget {
  const InvitationsPage({super.key});

  @override
  State<InvitationsPage> createState() => _InvitationsPageState();
}

class _InvitationsPageState extends State<InvitationsPage> {
  late Future<List<EventInvitationModel>> _future;
  final Set<String> _acceptingIds = {};
  final Set<String> _deletingIds = {};
  final TextEditingController _joinCodeController = TextEditingController();
  bool _joiningByCode = false;

  @override
  void initState() {
    super.initState();
    _future = _loadInvitations();
  }

  @override
  void dispose() {
    _joinCodeController.dispose();
    super.dispose();
  }

  Future<List<EventInvitationModel>> _loadInvitations() async {
    final responses = await Future.wait([
      DioHelper.get('/event-members/mine'),
      DioHelper.get('/event/my-photographer-invitations'),
    ]);

    final teamData = responses[0].data['data'] as List? ?? [];
    final teamInvitations = teamData
        .where((item) {
          final role = (item as Map)['role']?.toString();
          return role == 'photographer' || role == 'assistant_photographer';
        })
        .map(
          (item) => EventInvitationModel.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();

    final teamEventIds = teamInvitations
        .map((item) => item.event?.id)
        .whereType<String>()
        .toSet();
    final legacyData = responses[1].data['data'] as List? ?? [];
    final legacyInvitations = legacyData
        .map(
          (item) => EventInvitationModel.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .where((item) => !teamEventIds.contains(item.event?.id));

    final invitations = [...teamInvitations, ...legacyInvitations];
    invitations.sort((a, b) {
      if (a.isPending != b.isPending) return a.isPending ? -1 : 1;
      return (b.createdAt ?? '').compareTo(a.createdAt ?? '');
    });
    return invitations;
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _loadInvitations();
    });
    await _future;
  }

  Future<void> _accept(EventInvitationModel invitation) async {
    setState(() => _acceptingIds.add(invitation.id));
    try {
      final mutation = useCommonMutationApi<Map<String, dynamic>, String>(
        config: MutationConfig<Map<String, dynamic>, String>(
          url: invitation.isTeamMembership
              ? '/event-members/accept'
              : '/event/accept-invitation',
          method: HttpMethod.patch,
          mutationKey: 'accept-invitation-${invitation.id}',
          successMessage: 'Invitation accepted',
          body: (_) => null,
          queryParameters: (id) => {'id': id},
          fromJson: (json) => Map<String, dynamic>.from(json as Map),
        ),
      );

      final state = await mutation.mutate(invitation.id);
      if (state.data?.isSuccess ?? false) {
        await _refresh();
      }
    } catch (_) {
      AppToast.error('Failed to accept invitation');
    } finally {
      if (mounted) {
        setState(() => _acceptingIds.remove(invitation.id));
      }
    }
  }

  Future<void> _delete(EventInvitationModel invitation) async {
    setState(() => _deletingIds.add(invitation.id));
    try {
      final mutation = useCommonMutationApi<Map<String, dynamic>, String>(
        config: MutationConfig<Map<String, dynamic>, String>(
          url: invitation.isTeamMembership
              ? '/event-members/mine'
              : '/event/delete-invitation',
          method: HttpMethod.delete,
          mutationKey: 'delete-invitation-${invitation.id}',
          successMessage: 'Invitation deleted',
          queryParameters: (id) => {'id': id},
          fromJson: (json) => Map<String, dynamic>.from(json as Map),
        ),
      );

      final state = await mutation.mutate(invitation.id);
      if (state.data?.isSuccess ?? false) {
        await _refresh();
      }
    } catch (_) {
      AppToast.error('Failed to delete invitation');
    } finally {
      if (mounted) {
        setState(() => _deletingIds.remove(invitation.id));
      }
    }
  }

  Future<void> _joinWithCode() async {
    final code = _joinCodeController.text.trim().toUpperCase();
    if (code.length < 6) {
      AppToast.error('Enter a valid event join code');
      return;
    }
    setState(() => _joiningByCode = true);
    try {
      final response = await DioHelper.post(
        '/event-members/join',
        data: {'code': code},
      );
      final data = response.data is Map ? response.data['data'] : null;
      final eventData = data is Map ? data['eventId'] : null;
      if (eventData is Map) {
        final event = EventSummary.fromJson(
          Map<String, dynamic>.from(eventData),
        );
        if (event.id.isNotEmpty) {
          await ActiveEventStorage.saveActiveEvent(event);
        }
      }
      _joinCodeController.clear();
      AppToast.success('Joined event as photographer');
      await _refresh();
    } catch (error) {
      AppToast.error('Could not join event. Check the code and try again.');
    } finally {
      if (mounted) setState(() => _joiningByCode = false);
    }
  }

  Widget _joinCodeCard() {
    return AppSectionCard(
      title: 'Join event with code',
      icon: Icons.group_add_outlined,
      subtitle:
          'Paste the code shared by the Event Planner to join as a photographer.',
      children: [
        TextField(
          controller: _joinCodeController,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Event code',
            hintText: 'A1B2C3D4E5',
            prefixIcon: Icon(Icons.qr_code_2_outlined, size: 20),
          ),
          onSubmitted: (_) => _joiningByCode ? null : _joinWithCode(),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton.icon(
            onPressed: _joiningByCode ? null : _joinWithCode,
            icon: _joiningByCode
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.group_add_outlined),
            label: Text(_joiningByCode ? 'Joining...' : 'Join event'),
          ),
        ),
      ],
    );
  }

  Future<void> _activate(EventInvitationModel invitation) async {
    final event = invitation.event;
    if (event == null) {
      AppToast.error('Event details missing');
      return;
    }

    await ActiveEventStorage.saveActiveEvent(event);
    AppToast.success('Active event updated');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Invitations')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<EventInvitationModel>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text('Failed to load invitations: ${snapshot.error}'),
                ],
              );
            }

            final invitations = snapshot.data ?? [];

            return ValueListenableBuilder(
              valueListenable: ActiveEventStorage.activeEvent,
              builder: (context, activeEvent, _) {
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: invitations.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    if (index == 0) return _joinCodeCard();
                    final invitation = invitations[index - 1];
                    final event = invitation.event;
                    final isActive =
                        activeEvent != null && activeEvent.id == event?.id;
                    final isAccepting = _acceptingIds.contains(invitation.id);
                    final isDeleting = _deletingIds.contains(invitation.id);

                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                        border: Border.all(
                          color: isActive
                              ? AppColors.primary.withValues(alpha: 0.45)
                              : AppColors.border,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(
                              alpha: isActive ? 0.12 : 0.05,
                            ),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              AppIconTile(
                                icon: Icons.event_outlined,
                                size: 42,
                                iconSize: 21,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  event?.title ?? 'Untitled event',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.foreground,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              AppPill(
                                label: invitation.status,
                                icon: invitation.isPending
                                    ? Icons.schedule
                                    : invitation.isAccepted
                                    ? Icons.check_circle_outline
                                    : Icons.info_outline,
                                color: invitation.isPending
                                    ? AppColors.secondary
                                    : invitation.isAccepted
                                    ? Colors.green
                                    : AppColors.mutedForeground,
                              ),
                            ],
                          ),
                          if (event?.description?.isNotEmpty ?? false) ...[
                            const SizedBox(height: 10),
                            Text(
                              event!.description!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.45,
                                color: AppColors.mutedForeground,
                              ),
                            ),
                          ],
                          if (invitation.inviterName != null) ...[
                            const SizedBox(height: 10),
                            const Divider(height: 1),
                            AppInfoRow(
                              icon: Icons.person_outline,
                              label: 'Invited by',
                              value: invitation.inviterName!,
                            ),
                          ],
                          const SizedBox(height: 8),
                          if (invitation.isPending)
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: FilledButton(
                                onPressed: isAccepting
                                    ? null
                                    : () => _accept(invitation),
                                child: isAccepting
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text('Accept invitation'),
                              ),
                            )
                          else if (invitation.isAccepted)
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: FilledButton.tonal(
                                onPressed: isActive
                                    ? null
                                    : () => _activate(invitation),
                                child: Text(
                                  isActive
                                      ? 'Active upload event'
                                      : 'Make active event',
                                ),
                              ),
                            ),
                          const SizedBox(height: 4),
                          SizedBox(
                            width: double.infinity,
                            child: TextButton.icon(
                              onPressed: isDeleting
                                  ? null
                                  : () => _delete(invitation),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.destructive,
                              ),
                              icon: const Icon(Icons.delete_outline, size: 18),
                              label: isDeleting
                                  ? const Text('Deleting...')
                                  : const Text('Delete invitation'),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}
