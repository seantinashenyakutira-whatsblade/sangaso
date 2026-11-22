import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_date.dart';

enum NotificationType {
  bookingRequest,
  bookingAccepted,
  bookingDeclined,
  bookingCancelled,
  jobStarted,
  jobCompleted,
  newMessage,
  system,
}

class NotificationModel {
  final String id;
  final String userId; // Recipient
  final String title;
  final String message;
  final NotificationType type;
  final String? relatedId; // bookingId or other related entity ID
  final bool isRead;
  final DateTime createdAt;

  NotificationModel({
    required this.id,
    required this.userId,
    required this.title,
    required this.message,
    required this.type,
    this.relatedId,
    this.isRead = false,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'title': title,
      'message': message,
      // The website renders notification text from `body`; write both so
      // notifications created on either client display everywhere.
      'body': message,
      'type': type.name,
      'relatedId': relatedId,
      'isRead': isRead,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory NotificationModel.fromMap(Map<String, dynamic> map) {
    return NotificationModel(
      id: map['id'] ?? '',
      userId: map['userId'] ?? '',
      title: map['title'] ?? '',
      // Website notifications store the text as `body`; Android
      // notifications use `message`. Read either.
      message: map['message'] ?? map['body'] ?? '',
      type: NotificationType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => NotificationType.system,
      ),
      relatedId: map['relatedId'],
      isRead: map['isRead'] ?? false,
      createdAt: parseFirestoreDate(map['createdAt'], field: 'createdAt'),
    );
  }

  /// Builds a notification from a Firestore document, falling back to the
  /// document ID when the payload has no usable `id` field (website-created
  /// notifications are added with an auto-generated document ID only).
  factory NotificationModel.fromDoc(DocumentSnapshot<Object?> doc) {
    final raw = doc.data();
    final data = raw is Map<String, dynamic> ? raw : <String, dynamic>{};
    final storedId = data['id'];
    return NotificationModel.fromMap({
      ...data,
      'id': storedId is String && storedId.isNotEmpty ? storedId : doc.id,
    });
  }

  // ADD THIS copyWith METHOD
  NotificationModel copyWith({
    String? id,
    String? userId,
    String? title,
    String? message,
    NotificationType? type,
    String? relatedId,
    bool? isRead,
    DateTime? createdAt,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      message: message ?? this.message,
      type: type ?? this.type,
      relatedId: relatedId ?? this.relatedId,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
