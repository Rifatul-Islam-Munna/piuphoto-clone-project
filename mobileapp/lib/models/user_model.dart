class UserModel {
  const UserModel({
    this.id,
    this.mongoId,
    this.name,
    this.userId,
    this.email,
    this.phone,
    this.whatsapp,
    this.role,
    this.isPublished,
    this.isActive,
    this.isEmailVerified,
    this.gender,
    this.maritalStatus,
    this.age,
    this.bloodGroup,
    this.weight,
    this.subscriptionPlan,
    this.isSubscriber,
    this.creditsValue,
    this.subscriptionStartDate,
    this.subscriptionEndDate,
    this.profileImage,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String? mongoId;
  final String? name;
  final String? userId;
  final String? email;
  final String? phone;
  final String? whatsapp;
  final String? role;
  final bool? isPublished;
  final bool? isActive;
  final bool? isEmailVerified;
  final String? gender;
  final String? maritalStatus;
  final int? age;
  final String? bloodGroup;
  final int? weight;
  final dynamic subscriptionPlan;
  final bool? isSubscriber;
  final int? creditsValue;
  final String? subscriptionStartDate;
  final String? subscriptionEndDate;
  final Map<String, dynamic>? profileImage;
  final String? createdAt;
  final String? updatedAt;

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id']?.toString(),
      mongoId: json['_id']?.toString(),
      name: json['name']?.toString(),
      userId: json['userId']?.toString(),
      email: json['email']?.toString(),
      phone: json['phone']?.toString(),
      whatsapp: json['whatsapp']?.toString(),
      role: json['role']?.toString(),
      isPublished: json['isPublished'] as bool?,
      isActive: json['isActive'] as bool?,
      isEmailVerified: json['isEmailVerified'] as bool?,
      gender: json['gender']?.toString(),
      maritalStatus: json['maritalStatus']?.toString(),
      age: (json['age'] as num?)?.toInt(),
      bloodGroup: json['bloodGroup']?.toString(),
      weight: (json['weight'] as num?)?.toInt(),
      subscriptionPlan: _dynamicFromJson(json['subscriptionPlanId']),
      isSubscriber: json['isSubscriber'] as bool?,
      creditsValue: (json['credits'] as num?)?.toInt(),
      subscriptionStartDate: json['subscriptionStartDate']?.toString(),
      subscriptionEndDate: json['subscriptionEndDate']?.toString(),
      profileImage: json['profileImage'] is Map
          ? Map<String, dynamic>.from(json['profileImage'] as Map)
          : null,
      createdAt: json['createdAt']?.toString(),
      updatedAt: json['updatedAt']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      '_id': mongoId,
      'name': name,
      'userId': userId,
      'email': email,
      'phone': phone,
      'whatsapp': whatsapp,
      'role': role,
      'isPublished': isPublished,
      'isActive': isActive,
      'isEmailVerified': isEmailVerified,
      'gender': gender,
      'maritalStatus': maritalStatus,
      'age': age,
      'bloodGroup': bloodGroup,
      'weight': weight,
      'subscriptionPlanId': subscriptionPlan,
      'isSubscriber': isSubscriber,
      'credits': creditsValue,
      'subscriptionStartDate': subscriptionStartDate,
      'subscriptionEndDate': subscriptionEndDate,
      'profileImage': profileImage,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  static dynamic _dynamicFromJson(dynamic value) {
    if (value == null || value is String) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return value.toString();
  }

  String get stableId => id ?? mongoId ?? '';

  String get displayLabel {
    if (name != null && name!.trim().isNotEmpty) {
      return name!.trim();
    }
    if (email != null && email!.trim().isNotEmpty) {
      return email!.trim();
    }
    if (phone != null && phone!.trim().isNotEmpty) {
      return phone!.trim();
    }
    return 'User';
  }

  String get avatarText {
    final label = displayLabel.trim();
    return label.isEmpty ? 'U' : label[0].toUpperCase();
  }

  int get credits => creditsValue ?? 0;

  bool get hasLowCredits => credits < 5;

  String get normalizedRole => role?.trim().toLowerCase() ?? '';

  bool get isPhotographer => normalizedRole == 'photographer';

  bool get isAdmin => normalizedRole == 'admin';

  bool get isUser => normalizedRole == 'user';
}
