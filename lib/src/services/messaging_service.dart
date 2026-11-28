import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../models/message_model.dart';

abstract class MessagingService {
  Stream<List<MessageModel>> getMessages(String bookingId);
  Future<void> sendMessage({
    required String bookingId,
    required String senderId,
    required String text,
    String? imageUrl,
  });
}

class SenderNotAllowedException implements Exception {
  final String bookingId;
  final String senderId;
  const SenderNotAllowedException(this.bookingId, this.senderId);

  @override
  String toString() =>
      'Sender is not a participant in this conversation (booking: '
      '$bookingId).';
}

class FirebaseMessagingService implements MessagingService {
  final FirebaseFirestore? _firestoreOverride;
  final _uuid = const Uuid();

  FirebaseMessagingService({FirebaseFirestore? firestore})
      : _firestoreOverride = firestore;

  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  @override
  Stream<List<MessageModel>> getMessages(String bookingId) {
    return _firestore
        .collection('bookings')
        .doc(bookingId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => MessageModel.fromDoc(doc))
              .toList(),
        );
  }

  @override
  Future<void> sendMessage({
    required String bookingId,
    required String senderId,
    required String text,
    String? imageUrl,
  }) async {
    if (text.trim().isEmpty && imageUrl == null) {
      throw ArgumentError('A message needs text or an image before sending.');
    }

    // The booking is readable only by its participants; Rules independently
    // enforce that senderId and receiverId are the two booking participants.
    final bookingDoc =
        await _firestore.collection('bookings').doc(bookingId).get();
    if (!bookingDoc.exists) {
      throw StateError('Booking $bookingId does not exist.');
    }
    final data = bookingDoc.data()!;
    final seekerId = data['seekerId'] as String?;
    final providerId = data['providerId'] as String?;
    if (senderId.isEmpty ||
        (senderId != seekerId && senderId != providerId)) {
      throw SenderNotAllowedException(bookingId, senderId);
    }
    final receiverId = senderId == seekerId ? providerId : seekerId;
    if (receiverId == null || receiverId.isEmpty) {
      throw StateError('Booking $bookingId has no message recipient.');
    }

    final message = MessageModel(
      id: _uuid.v4(),
      bookingId: bookingId,
      senderId: senderId,
      receiverId: receiverId,
      text: text,
      imageUrl: imageUrl,
      timestamp: DateTime.now(),
    );

    await _firestore
        .collection('bookings')
        .doc(bookingId)
        .collection('messages')
        .doc(message.id)
        .set(message.toMap());
  }
}
