class EventSummary {
  const EventSummary({
    required this.id,
    required this.title,
    this.description,
    this.imageUrl,
    this.photosCount = 0,
  });

  final String id;
  final String title;
  final String? description;
  final String? imageUrl;
  final int photosCount;

  static int _intFromJson(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  factory EventSummary.fromJson(Map<String, dynamic> json) {
    final image = json['image'];
    return EventSummary(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Untitled event',
      description: json['description']?.toString(),
      imageUrl: image is Map ? image['url']?.toString() : null,
      photosCount: _intFromJson(json['photosCount']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'title': title,
      'description': description,
      'image': imageUrl == null ? null : {'url': imageUrl},
      'photosCount': photosCount,
    };
  }
}

class EventInvitationModel {
  const EventInvitationModel({
    required this.id,
    required this.status,
    this.createdAt,
    this.respondedAt,
    this.event,
    this.inviterName,
    this.isTeamMembership = false,
    this.teamRole,
  });

  final String id;
  final String status;
  final String? createdAt;
  final String? respondedAt;
  final EventSummary? event;
  final String? inviterName;
  final bool isTeamMembership;
  final String? teamRole;

  factory EventInvitationModel.fromJson(Map<String, dynamic> json) {
    final isTeamMembership = json['eventId'] is Map;
    final event = isTeamMembership ? json['eventId'] : json['event'];
    final inviter = isTeamMembership ? json['invitedBy'] : json['inviter'];
    final rawStatus = json['status']?.toString() ?? 'pending';

    return EventInvitationModel(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      status: rawStatus == 'active' ? 'accepted' : rawStatus,
      createdAt: json['createdAt']?.toString(),
      respondedAt: json['respondedAt']?.toString(),
      event: event is Map
          ? EventSummary.fromJson(Map<String, dynamic>.from(event))
          : null,
      inviterName: inviter is Map
          ? (inviter['name'] ?? inviter['email'] ?? inviter['phone'])
                ?.toString()
          : null,
      isTeamMembership: isTeamMembership,
      teamRole: json['role']?.toString(),
    );
  }

  bool get isPending => status.toLowerCase() == 'pending';

  bool get isAccepted => status.toLowerCase() == 'accepted';
}
