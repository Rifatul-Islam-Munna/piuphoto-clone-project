import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:mobileapp/core/network/dio_helper.dart';
import 'package:mobileapp/core/network/mutation_wrapper.dart';
import 'package:mobileapp/core/storage/active_event_storage.dart';
import 'package:mobileapp/models/event_invitation_model.dart';
import 'package:mobileapp/utilities/app_toast.dart';

@RoutePage()
class InvitationsPage extends StatefulWidget {
  const InvitationsPage({super.key});

  @override
  State<InvitationsPage> createState() => _InvitationsPageState();
}

class _InvitationsPageState extends State<InvitationsPage> {
  late Future<List<EventInvitationModel>> _future;
  final Set<String> _acceptingIds = {};

  @override
  void initState() {
    super.initState();
    _future = _loadInvitations();
  }

  Future<List<EventInvitationModel>> _loadInvitations() async {
    final response = await DioHelper.get('/event/my-photographer-invitations');
    final data = response.data['data'] as List? ?? [];
    final invitations = data
        .map(
          (item) => EventInvitationModel.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();

    invitations.sort((a, b) {
      if (a.isPending != b.isPending) {
        return a.isPending ? -1 : 1;
      }
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
          url: '/event/accept-invitation',
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
            if (invitations.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(24),
                children: const [
                  Text('No invitations yet.'),
                ],
              );
            }

            return ValueListenableBuilder(
              valueListenable: ActiveEventStorage.activeEvent,
              builder: (context, activeEvent, _) {
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: invitations.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final invitation = invitations[index];
                    final event = invitation.event;
                    final isActive =
                        activeEvent != null && activeEvent.id == event?.id;
                    final isAccepting = _acceptingIds.contains(invitation.id);

                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    event?.title ?? 'Untitled event',
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                ),
                                Chip(label: Text(invitation.status)),
                              ],
                            ),
                            if (event?.description?.isNotEmpty ?? false) ...[
                              const SizedBox(height: 8),
                              Text(event!.description!),
                            ],
                            if (invitation.inviterName != null) ...[
                              const SizedBox(height: 8),
                              Text('From: ${invitation.inviterName}'),
                            ],
                            const SizedBox(height: 12),
                            if (invitation.isPending)
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: isAccepting
                                      ? null
                                      : () => _accept(invitation),
                                  child: isAccepting
                                      ? const CircularProgressIndicator()
                                      : const Text('Accept invitation'),
                                ),
                              )
                            else if (invitation.isAccepted)
                              SizedBox(
                                width: double.infinity,
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
                          ],
                        ),
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
