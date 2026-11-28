import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_date.dart';

class MessageModel {
  final String id;
  final String bookingId;
  final String senderId;
  final String receiverId;
  final String text;
  final String? imageUrl;
  final DateTime timestamp;
  final bool isRead;

  MessageModel({
    required this.id,
    required this.bookingId,
    required this.senderId,
    required this.receiverId,
    required this.text,
    this.imageUrl,
    required this.timestamp,
    this.isRead = false,
  });

  /// The document ID is the message ID; it is not duplicated in the payload.
  /// Null optional fields are omitted so writes match the strict rules.
  Map<String, dynamic> toMap() {
    final data = <String, dynamic>{
      'bookingId': bookingId,
      'senderId': senderId,
      'receiverId': receiverId,
      'text': text,
      'timestamp': Timestamp.fromDate(timestamp),
      'isRead': isRead,
    };
    if (imageUrl != null) {
      data['imageUrl'] = imageUrl;
    }
    return data;
  }

  factory MessageModel.fromMap(Map<String, dynamic> map, {String? fallbackId}) {
    final storedId = map['id'];
    return MessageModel(
      id: storedId is String && storedId.isNotEmpty
          ? storedId
          : (fallbackId ?? ''),
      bookingId: map['bookingId'] ?? '',
      senderId: map['senderId'] ?? '',
      receiverId: map['receiverId'] ?? '',
      text: map['text'] ?? '',
      imageUrl: map['imageUrl'],
      timestamp: parseFirestoreDate(map['timestamp'], field: 'timestamp'),
      isRead: map['isRead'] ?? false,
    );
  }

  factory MessageModel.fromDoc(DocumentSnapshot<Object?> doc) {
    final raw = doc.data();
    final data = raw is Map<String, dynamic> ? raw : <String, dynamic>{};
    return MessageModel.fromMap(data, fallbackId: doc.id);
  }
}
