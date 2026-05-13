class EventSummary {
  const EventSummary({
    required this.id,
    required this.title,
    this.description,
    this.imageUrl,
  });

  final String id;
  final String title;
  final String? description;
  final String? imageUrl;

  factory EventSummary.fromJson(Map<String, dynamic> json) {
    final image = json['image'];
    return EventSummary(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Untitled event',
      description: json['description']?.toString(),
      imageUrl: image is Map ? image['url']?.toString() : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'title': title,
      'description': description,
      'image': imageUrl == null ? null : {'url': imageUrl},
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
  });

  final String id;
  final String status;
  final String? createdAt;
  final String? respondedAt;
  final EventSummary? event;
  final String? inviterName;

  factory EventInvitationModel.fromJson(Map<String, dynamic> json) {
    final event = json['event'];
    final inviter = json['inviter'];

    return EventInvitationModel(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      createdAt: json['createdAt']?.toString(),
      respondedAt: json['respondedAt']?.toString(),
      event: event is Map
          ? EventSummary.fromJson(Map<String, dynamic>.from(event))
          : null,
      inviterName: inviter is Map
          ? (inviter['name'] ?? inviter['email'] ?? inviter['phone'])
              ?.toString()
          : null,
    );
  }

  bool get isPending => status.toLowerCase() == 'pending';

  bool get isAccepted => status.toLowerCase() == 'accepted';
}
