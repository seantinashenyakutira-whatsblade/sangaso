import 'dart:async';

import 'package:sangaso/src/models/notification_model.dart';

import '../services/notification_service.dart';

/// In-memory notification service for previews/tests.
///
/// It intentionally exposes only the client-safe read/mark APIs; notification
/// creation belongs to trusted backend Functions in the Firebase service.
class MockNotificationService implements NotificationService {
  final List<NotificationModel> _notifications = [];
  final StreamController<List<NotificationModel>> _controller =
      StreamController<List<NotificationModel>>.broadcast();

  MockNotificationService() {
    _notifications.addAll([
      NotificationModel(
        id: 'notification_1',
        userId: 'mock_user_1',
        title: 'New Booking Request',
        message: 'John Doe has requested your plumbing service',
        type: NotificationType.bookingRequest,
        relatedId: 'mock_booking_1',
        isRead: false,
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      ),
      NotificationModel(
        id: 'notification_2',
        userId: 'mock_user_1',
        title: 'Booking Accepted',
        message: 'Your booking request has been accepted',
        type: NotificationType.bookingAccepted,
        relatedId: 'mock_booking_2',
        isRead: false,
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      ),
      NotificationModel(
        id: 'notification_3',
        userId: 'mock_user_1',
        title: 'Job Completed',
        message: 'Your plumbing job has been marked as completed',
        type: NotificationType.jobCompleted,
        relatedId: 'mock_booking_3',
        isRead: true,
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
    ]);
    _controller.add(List.from(_notifications));
  }

  @override
  Stream<List<NotificationModel>> getUserNotifications(String userId) {
    return _controller.stream.map(
      (notifications) =>
          notifications.where((n) => n.userId == userId).toList(),
    );
  }

  @override
  Stream<int> getUnreadCount(String userId) {
    return _controller.stream.map((notifications) {
      return notifications.where((n) => n.userId == userId && !n.isRead).length;
    });
  }

  @override
  Future<void> markAllAsRead(String userId) async {
    await Future.delayed(const Duration(milliseconds: 300));
    for (var i = 0; i < _notifications.length; i++) {
      if (_notifications[i].userId == userId) {
        _notifications[i] = _notifications[i].copyWith(isRead: true);
      }
    }
    _controller.add(List.from(_notifications));
  }

  @override
  Future<void> markAsRead(String notificationId) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final index = _notifications.indexWhere((n) => n.id == notificationId);
    if (index != -1) {
      _notifications[index] = _notifications[index].copyWith(isRead: true);
      _controller.add(List.from(_notifications));
    }
  }

  @override
  Future<void> checkNotificationData(String userId) async {
    for (final notification in _notifications) {
      if (notification.userId == userId) {
        // Read-only probe, mirrors the Firebase implementation.
        notification.isRead;
      }
    }
  }
}
