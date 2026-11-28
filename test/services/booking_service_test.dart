import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sangaso/src/models/booking_model.dart';
import 'package:sangaso/src/services/booking_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    await firestore.collection('users').doc('seeker-1').set({
      'id': 'seeker-1',
      'email': 'jane@example.com',
      'displayName': 'Jane Seeker',
      'phoneNumber': '+260977000001',
      'role': 'seeker',
      'isBanned': false,
      'isSuspended': false,
    });
    await firestore.collection('publicProfiles').doc('provider-1').set({
      'id': 'provider-1',
      'role': 'provider',
      'displayName': 'David Provider',
      'tradingName': 'Dave Plumbing',
      'category': 'Plumbing',
      'city': 'Lusaka',
      'basePrice': 250,
      'kycApproved': true,
      'isBanned': false,
      'isSuspended': false,
    });
  });

  group('FirebaseBookingService', () {
    test('createBooking writes non-PII provider display data only', () async {
      final bookingService = FirebaseBookingService(firestore: firestore);

      final id = await bookingService.createBooking(
        seekerId: 'seeker-1',
        providerId: 'provider-1',
        serviceType: 'Plumbing',
        scheduledTime: DateTime(2026, 10, 20, 9, 30),
        address: '12 Nakonde Road',
        price: 250,
      );

      final doc = await firestore.collection('bookings').doc(id).get();
      expect(doc.exists, isTrue);
      final raw = doc.data()!;
      expect(raw.containsKey('providerEmail'), isFalse);
      expect(raw.containsKey('providerPhone'), isFalse);
      expect(raw.containsKey('seekerEmail'), isFalse);

      final booking = BookingModel.fromMap(raw);
      expect(booking.status, BookingStatus.requested);
      expect(booking.seekerName, 'Jane Seeker');
      expect(booking.providerName, 'Dave Plumbing');
      expect(booking.price, 250);
    });

    test('createBooking does not create client-owned notifications', () async {
      final bookingService = FirebaseBookingService(firestore: firestore);

      await bookingService.createBooking(
        seekerId: 'seeker-1',
        providerId: 'provider-1',
        serviceType: 'Plumbing',
        scheduledTime: DateTime(2026, 10, 20, 9, 30),
        address: '12 Nakonde Road',
        price: 250,
      );

      final notifications = await firestore.collection('notifications').get();
      expect(notifications.docs, isEmpty);
    });

    test('createBooking persists the origin service and its price', () async {
      final bookingService = FirebaseBookingService(firestore: firestore);

      final id = await bookingService.createBooking(
        seekerId: 'seeker-1',
        providerId: 'provider-1',
        serviceType: 'Pine Plumbing Repair',
        scheduledTime: DateTime(2026, 10, 20, 9, 30),
        address: '12 Nakonde Road',
        price: 1300,
        serviceId: 'svc-42',
        serviceName: 'Pine Plumbing Repair',
      );

      final booking = BookingModel.fromMap(
          (await firestore.collection('bookings').doc(id).get()).data()!);
      expect(booking.price, 1300);
      expect(booking.serviceId, 'svc-42');
      expect(booking.serviceName, 'Pine Plumbing Repair');
      expect(booking.serviceType, 'Pine Plumbing Repair');
    });

    test('legacy bookings without service references remain readable',
        () async {
      await firestore.collection('bookings').doc('legacy-1').set({
        'id': 'legacy-1',
        'seekerId': 'seeker-1',
        'providerId': 'provider-1',
        'serviceType': 'Plumbing',
        'scheduledTime':
            Timestamp.fromDate(DateTime(2026, 10, 20, 9, 30)),
        'address': '12 Nakonde Road',
        'price': 1000,
        'status': 'requested',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });
      final booking = BookingModel.fromMap(
          (await firestore.collection('bookings').doc('legacy-1').get())
              .data()!);
      expect(booking.serviceId, isNull);
      expect(booking.serviceName, isNull);
      expect(booking.price, 1000);
    });

    test('status transitions write timestamps without client notifications',
        () async {
      final bookingService = FirebaseBookingService(firestore: firestore);

      final id = await bookingService.createBooking(
        seekerId: 'seeker-1',
        providerId: 'provider-1',
        serviceType: 'Plumbing',
        scheduledTime: DateTime(2026, 10, 20, 9, 30),
        address: '12 Nakonde Road',
        price: 250,
      );

      await bookingService.updateBookingStatus(id, BookingStatus.accepted);
      var booking = BookingModel.fromMap(
          (await firestore.collection('bookings').doc(id).get()).data()!);
      expect(booking.status, BookingStatus.accepted);
      expect(booking.acceptedAt, isNotNull);

      await bookingService.updateBookingStatus(id, BookingStatus.inProgress);
      booking = BookingModel.fromMap(
          (await firestore.collection('bookings').doc(id).get()).data()!);
      expect(booking.status, BookingStatus.inProgress);
      expect(booking.startedAt, isNotNull);

      await bookingService.updateBookingStatus(id, BookingStatus.completed);
      booking = BookingModel.fromMap(
          (await firestore.collection('bookings').doc(id).get()).data()!);
      expect(booking.status, BookingStatus.completed);
      expect(booking.completedAt, isNotNull);

      final raw = (await firestore.collection('bookings').doc(id).get()).data()!;
      expect(raw['updatedAt'], isNotNull);
      expect((await firestore.collection('notifications').get()).docs, isEmpty);
    });

    test('updateBookingStatus is a no-op for an unknown booking', () async {
      final bookingService = FirebaseBookingService(firestore: firestore);
      await bookingService.updateBookingStatus(
          'does-not-exist', BookingStatus.accepted);
    });

    test('idempotent retry of an identical open request does not duplicate',
        () async {
      final bookingService = FirebaseBookingService(firestore: firestore);

      final id1 = await bookingService.createBooking(
        seekerId: 'seeker-1',
        providerId: 'provider-1',
        serviceType: 'Plumbing',
        scheduledTime: DateTime.utc(2026, 10, 20, 7, 30),
        address: '12 Nakonde Road',
        price: 250,
      );
      final id2 = await bookingService.createBooking(
        seekerId: 'seeker-1',
        providerId: 'provider-1',
        serviceType: 'Plumbing',
        scheduledTime: DateTime.utc(2026, 10, 20, 7, 30),
        address: '12 Nakonde Road',
        price: 250,
      );

      expect(id2, id1);
      expect((await firestore.collection('bookings').get()).docs, hasLength(1));
      expect((await firestore.collection('notifications').get()).docs, isEmpty);
    });

    test('rejects a provider whose public profile is not discoverable',
        () async {
      await firestore.collection('publicProfiles').doc('hidden-1').set({
        'role': 'provider',
        'kycApproved': false,
        'isBanned': false,
        'isSuspended': false,
      });
      final bookingService = FirebaseBookingService(firestore: firestore);

      await expectLater(
        bookingService.createBooking(
          seekerId: 'seeker-1',
          providerId: 'hidden-1',
          serviceType: 'Plumbing',
          scheduledTime: DateTime(2026, 10, 20, 9, 30),
          address: '12 Nakonde Road',
          price: 250,
        ),
        throwsA(isA<StateError>()),
      );
      expect((await firestore.collection('bookings').get()).docs, isEmpty);
    });

    test('getBookingsForUser returns seeker bookings newest first', () async {
      final bookingService = FirebaseBookingService(firestore: firestore);

      final firstId = await bookingService.createBooking(
        seekerId: 'seeker-1',
        providerId: 'provider-1',
        serviceType: 'Plumbing',
        scheduledTime: DateTime(2026, 10, 21, 10, 0),
        address: '12 Nakonde Road',
        price: 250,
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final secondId = await bookingService.createBooking(
        seekerId: 'seeker-1',
        providerId: 'provider-1',
        serviceType: 'Electrical',
        scheduledTime: DateTime(2026, 10, 22, 10, 0),
        address: '13 Nakonde Road',
        price: 180,
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));

      final bookings = await bookingService
          .getBookingsForUser('seeker-1', false)
          .first;
      expect(bookings.map((b) => b.id), [secondId, firstId]);
    });
  });
}
