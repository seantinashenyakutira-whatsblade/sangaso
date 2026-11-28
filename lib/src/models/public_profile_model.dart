import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_date.dart';

/// Non-PII projection used for provider and seeker discovery.
///
/// Clients must read this collection instead of `users/{uid}`, which remains
/// self/admin-only. This model deliberately has no email, phone, or address
/// fields and offers no write map: `publicProfiles` is backend-maintained.
class PublicProfileModel {
  final String id;
  final String role;
  final String? displayName;
  final String? tradingName;
  final String? category;
  final String? city;
  final String? photoUrl;
  final double? basePrice;
  final String? bio;
  final bool kycApproved;
  final bool isBanned;
  final bool isSuspended;
  final DateTime? updatedAt;

  const PublicProfileModel({
    required this.id,
    required this.role,
    this.displayName,
    this.tradingName,
    this.category,
    this.city,
    this.photoUrl,
    this.basePrice,
    this.bio,
    this.kycApproved = false,
    this.isBanned = false,
    this.isSuspended = false,
    this.updatedAt,
  });

  bool get isProvider => role == 'provider' || role == 'admin';

  bool get isDiscoverable =>
      isProvider && kycApproved && !isBanned && !isSuspended;

  factory PublicProfileModel.fromMap(
    Map<String, dynamic> map, {
    String? fallbackId,
  }) {
    final storedId = map['id'];
    return PublicProfileModel(
      id: storedId is String && storedId.isNotEmpty
          ? storedId
          : (fallbackId ?? ''),
      role: map['role'] is String ? map['role'] as String : 'seeker',
      displayName: map['displayName'] as String?,
      tradingName: map['tradingName'] as String?,
      category: map['category'] as String?,
      city: map['city'] as String?,
      photoUrl: map['photoUrl'] as String?,
      basePrice: (map['basePrice'] as num?)?.toDouble(),
      bio: map['bio'] as String?,
      kycApproved: map['kycApproved'] == true,
      isBanned: map['isBanned'] == true,
      isSuspended: map['isSuspended'] == true,
      updatedAt: parseFirestoreDateOrNull(map['updatedAt'], field: 'updatedAt'),
    );
  }

  factory PublicProfileModel.fromDoc(DocumentSnapshot<Object?> doc) {
    final raw = doc.data();
    final data = raw is Map<String, dynamic> ? raw : <String, dynamic>{};
    return PublicProfileModel.fromMap(data, fallbackId: doc.id);
  }
}
