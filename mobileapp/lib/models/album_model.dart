class AlbumModel {
  const AlbumModel({
    required this.id,
    required this.title,
    this.description,
    this.eventId,
    this.imagesCount = 0,
  });

  final String id;
  final String title;
  final String? description;
  final String? eventId;
  final int imagesCount;

  factory AlbumModel.fromJson(Map<String, dynamic> json) {
    final event = json['eventId'];
    return AlbumModel(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Untitled album',
      description: json['description']?.toString(),
      imagesCount: int.tryParse(json['imagesCount']?.toString() ?? '') ?? 0,
      eventId: event is Map
          ? (event['_id'] ?? event['id'])?.toString()
          : event?.toString(),
    );
  }
}
