class AlbumModel {
  const AlbumModel({
    required this.id,
    required this.title,
    this.description,
    this.eventId,
  });

  final String id;
  final String title;
  final String? description;
  final String? eventId;

  factory AlbumModel.fromJson(Map<String, dynamic> json) {
    final event = json['eventId'];
    return AlbumModel(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Untitled album',
      description: json['description']?.toString(),
      eventId: event is Map
          ? (event['_id'] ?? event['id'])?.toString()
          : event?.toString(),
    );
  }
}
