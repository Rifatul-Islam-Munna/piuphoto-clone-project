class EventImageModel {
  const EventImageModel({
    required this.id,
    required this.imageUrl,
    this.isEnhanced = false,
    this.createdAt,
    this.takenBy,
    this.albumId,
    this.albumTitle,
  });

  final String id;
  final String imageUrl;
  final bool isEnhanced;
  final String? createdAt;
  final String? takenBy;
  final String? albumId;
  final String? albumTitle;

  factory EventImageModel.fromJson(Map<String, dynamic> json) {
    final userTakenBy = json['userTakenBy'];
    final album = json['albumId'];

    return EventImageModel(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      imageUrl: json['imageUrl']?.toString() ?? '',
      isEnhanced: json['isEnhanced'] == true,
      createdAt: json['createdAt']?.toString(),
      takenBy: userTakenBy is Map
          ? (userTakenBy['name'] ??
                  userTakenBy['email'] ??
                  userTakenBy['phone'] ??
                  userTakenBy['userId'])
              ?.toString()
          : null,
      albumId: album is Map
          ? (album['_id'] ?? album['id'])?.toString()
          : album?.toString(),
      albumTitle: album is Map ? album['title']?.toString() : null,
    );
  }
}
