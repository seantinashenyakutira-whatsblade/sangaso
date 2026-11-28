import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../models/booking_model.dart';
import '../models/public_profile_model.dart';

abstract class BookingService {
  Future<String> createBooking({
    required String seekerId,
    required String providerId,
    required String serviceType,
    required DateTime scheduledTime,
    required String address,
    required double price,
    String? specialInstructions,
    String? serviceId,
    String? serviceName,
  });

  Stream<List<BookingModel>> getBookingsForUser(String userId, bool isProvider);
  Future<void> updateBookingStatus(String bookingId, BookingStatus status);
}

class FirebaseBookingService implements BookingService {
  final FirebaseFirestore? _firestoreOverride;

  FirebaseBookingService({FirebaseFirestore? firestore})
      : _firestoreOverride = firestore;

  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  @override
  Future<String> createBooking({
    required String seekerId,
    required String providerId,
    required String serviceType,
    required DateTime scheduledTime,
    required String address,
    required double price,
    String? specialInstructions,
    String? serviceId,
    String? serviceName,
  }) async {
    // The seeker reads only their own document; the provider is read from the
    // non-PII public projection because users/{uid} is self/admin-only.
    final seekerDoc = await _firestore.collection('users').doc(seekerId).get();
    final providerDoc = await _firestore
        .collection('publicProfiles')
        .doc(providerId)
        .get();

    if (!seekerDoc.exists || !providerDoc.exists) {
      throw StateError('Booking participant is not available.');
    }

    final seekerData = seekerDoc.data()!;
    if (seekerData['isBanned'] == true || seekerData['isSuspended'] == true) {
      throw StateError('This account cannot create bookings.');
    }

    final provider = PublicProfileModel.fromDoc(providerDoc);
    if (!provider.isDiscoverable) {
      throw StateError('This provider is not available for bookings.');
    }

    // Stable idempotency key: a client retrying an identical request
    // (same seeker, provider, slot and address) maps onto one booking.
    final fingerprint =
        '$seekerId|$providerId|${scheduledTime.toUtc().millisecondsSinceEpoch}|${address.trim().toLowerCase()}';
    var id = const Uuid().v5(
        '6ba7b811-9dad-11d1-80b4-00c04fd430c8', fingerprint);

    final existing = await _firestore.collection('bookings').doc(id).get();
    if (existing.exists && existing.data()!.containsKey('status')) {
      final activeStatuses = {'requested', 'accepted', 'inProgress'};
      if (activeStatuses.contains(existing.data()!['status'])) {
        return id;
      }
      // Previous identical request reached a terminal state - new booking.
      id = const Uuid().v5(
          '6ba7b811-9dad-11d1-80b4-00c04fd430c8',
          '$fingerprint|${DateTime.now().toIso8601String()}');
    }

    final booking = BookingModel(
      id: id,
      seekerId: seekerId,
      providerId: providerId,
      serviceType: serviceType,
      scheduledTime: scheduledTime,
      address: address,
      price: price,
      status: BookingStatus.requested,
      createdAt: DateTime.now(),
      // Non-PII display names only. Contacts and emails are not copied from
      // users/{uid}; backend triggers own notification creation.
      seekerName: seekerData['displayName'] as String?,
      providerName: provider.tradingName ?? provider.displayName ?? 'Provider',
      specialInstructions: specialInstructions,
      serviceId: serviceId,
      serviceName: serviceName,
    );

    await _firestore.collection('bookings').doc(id).set(booking.toMap());
    return id;
  }

  @override
  Stream<List<BookingModel>> getBookingsForUser(
    String userId,
    bool isProvider,
  ) {
    final field = isProvider ? 'providerId' : 'seekerId';
    return _firestore
        .collection('bookings')
        .where(field, isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
      final bookings = snapshot.docs
          .map((doc) => BookingModel.fromDoc(doc))
          .toList();
      bookings.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return bookings;
    });
  }

  @override
  Future<void> updateBookingStatus(
    String bookingId,
    BookingStatus status,
  ) async {
    final doc = await _firestore.collection('bookings').doc(bookingId).get();
    if (!doc.exists) return;

    final updateData = <String, dynamic>{
      'status': status.name,
      'updatedAt': Timestamp.now(),
    };

    switch (status) {
      case BookingStatus.accepted:
        updateData['acceptedAt'] = Timestamp.now();
        break;
      case BookingStatus.inProgress:
        updateData['startedAt'] = Timestamp.now();
        break;
      case BookingStatus.completed:
        updateData['completedAt'] = Timestamp.now();
        break;
      default:
        break;
    }

    await _firestore.collection('bookings').doc(bookingId).update(updateData);
  }

  Future<void> startJob(String bookingId) async {
    await updateBookingStatus(bookingId, BookingStatus.inProgress);
  }

  Future<void> completeJob(String bookingId) async {
    await updateBookingStatus(bookingId, BookingStatus.completed);
  }

  Future<void> cancelBooking(String bookingId) async {
    await updateBookingStatus(bookingId, BookingStatus.cancelled);
  }
}
