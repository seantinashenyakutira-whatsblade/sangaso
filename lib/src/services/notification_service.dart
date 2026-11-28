import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/notification_model.dart';

/// Read/mark-only client API for notifications.
///
/// Creation is owned exclusively by trusted backend Functions. Clients must
/// never write notification documents because strict rules deny create.
abstract class NotificationService {
  Stream<List<NotificationModel>> getUserNotifications(String userId);
  Stream<int> getUnreadCount(String userId);
  Future<void> markAllAsRead(String userId);
  Future<void> markAsRead(String notificationId);

  /// Read-only sanity probe used by diagnostics; performs no writes.
  Future<void> checkNotificationData(String userId);
}

class FirebaseNotificationService implements NotificationService {
  final FirebaseFirestore? _firestoreOverride;

  FirebaseNotificationService({FirebaseFirestore? firestore})
      : _firestoreOverride = firestore;

  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  @override
  Stream<List<NotificationModel>> getUserNotifications(String userId) {
    return _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => NotificationModel.fromDoc(doc))
          .toList();
    });
  }

  @override
  Stream<int> getUnreadCount(String userId) {
    return _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  @override
  Future<void> markAllAsRead(String userId) async {
    final batch = _firestore.batch();
    final snapshot = await _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .get();

    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {'isRead': true});
    }

    await batch.commit();
  }

  @override
  Future<void> markAsRead(String notificationId) async {
    await _firestore.collection('notifications').doc(notificationId).update({
      'isRead': true,
    });
  }

  @override
  Future<void> checkNotificationData(String userId) async {
    final snapshot = await _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .get();

    for (final doc in snapshot.docs) {
      // Touch the doc data so a malformed field surfaces as an exception.
      doc.data()['isRead'];
    }
  }
}
