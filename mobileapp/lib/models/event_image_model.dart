class EventImageModel {
  const EventImageModel({
    required this.id,
    required this.imageUrl,
    this.previewUrl,
    this.viewUrl,
    this.isEnhanced = false,
    this.isPublished = true,
    this.mediaType = 'photo',
    this.createdAt,
    this.takenBy,
    this.albumId,
    this.albumTitle,
  });

  final String id;
  final String imageUrl;
  final String? previewUrl;
  final String? viewUrl;
  String get displayUrl =>
      previewUrl?.isNotEmpty == true ? previewUrl! : imageUrl;
  String get fullViewUrl => viewUrl?.isNotEmpty == true ? viewUrl! : displayUrl;
  final bool isEnhanced;
  final bool isPublished;
  final String mediaType;
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
      previewUrl: json['previewUrl']?.toString(),
      viewUrl: json['viewUrl']?.toString(),
      isEnhanced: json['isEnhanced'] == true,
      isPublished: json['isPublished'] != false,
      mediaType: json['mediaType']?.toString() ?? 'photo',
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
