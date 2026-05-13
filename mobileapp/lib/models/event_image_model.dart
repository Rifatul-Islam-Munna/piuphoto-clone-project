class EventImageModel {
  const EventImageModel({
    required this.id,
    required this.imageUrl,
    this.referenceId,
    this.isEnhanced = false,
    this.createdAt,
    this.takenBy,
  });

  final String id;
  final String imageUrl;
  final String? referenceId;
  final bool isEnhanced;
  final String? createdAt;
  final String? takenBy;

  factory EventImageModel.fromJson(Map<String, dynamic> json) {
    final userTakenBy = json['userTakenBy'];

    return EventImageModel(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      imageUrl: json['imageUrl']?.toString() ?? '',
      referenceId: json['referenceId']?.toString(),
      isEnhanced: json['isEnhanced'] == true,
      createdAt: json['createdAt']?.toString(),
      takenBy: userTakenBy is Map
          ? (userTakenBy['name'] ??
                  userTakenBy['email'] ??
                  userTakenBy['phone'] ??
                  userTakenBy['userId'])
              ?.toString()
          : null,
    );
  }
}
