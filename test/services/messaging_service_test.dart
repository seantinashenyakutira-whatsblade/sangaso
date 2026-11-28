import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sangaso/src/models/message_model.dart';
import 'package:sangaso/src/services/messaging_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    await firestore.collection('bookings').doc('b-1').set({
      'id': 'b-1',
      'seekerId': 'seeker-1',
      'providerId': 'provider-1',
      'status': 'accepted',
    });
  });

  group('FirebaseMessagingService', () {
    test('sendMessage stamps sender and receiver without client notifications',
        () async {
      final messaging = FirebaseMessagingService(firestore: firestore);

      await messaging.sendMessage(
        bookingId: 'b-1',
        senderId: 'seeker-1',
        text: 'Is 9am still good?',
      );

      final messages = await firestore
          .collection('bookings')
          .doc('b-1')
          .collection('messages')
          .get();
      expect(messages.docs, hasLength(1));
      final data = messages.docs.first.data();
      expect(data['senderId'], 'seeker-1');
      expect(data['receiverId'], 'provider-1');
      expect(data['bookingId'], 'b-1');
      expect(data['text'], 'Is 9am still good?');
      expect(data.containsKey('id'), isFalse);
      expect(data['timestamp'], isNotNull);
      expect((await firestore.collection('notifications').get()).docs, isEmpty);
    });

    test('provider sending a message targets the seeker', () async {
      final messaging = FirebaseMessagingService(firestore: firestore);

      await messaging.sendMessage(
        bookingId: 'b-1',
        senderId: 'provider-1',
        text: 'On my way.',
      );

      final message = await firestore
          .collection('bookings')
          .doc('b-1')
          .collection('messages')
          .get();
      expect(message.docs.single.data()['receiverId'], 'seeker-1');
      expect((await firestore.collection('notifications').get()).docs, isEmpty);
    });

    test('getMessages falls back to the document id', () async {
      final messaging = FirebaseMessagingService(firestore: firestore);
      await messaging.sendMessage(
        bookingId: 'b-1',
        senderId: 'seeker-1',
        text: 'hello',
      );

      final messages = await messaging.getMessages('b-1').first;
      expect(messages.single.id, isNotEmpty);
      expect(messages.single.receiverId, 'provider-1');
    });

    test('rejects a sender that is not a participant of the booking',
        () async {
      final messaging = FirebaseMessagingService(firestore: firestore);

      await expectLater(
        messaging.sendMessage(
          bookingId: 'b-1',
          senderId: 'stranger-9',
          text: 'hello?',
        ),
        throwsA(isA<SenderNotAllowedException>()),
      );

      final messages = await firestore
          .collection('bookings')
          .doc('b-1')
          .collection('messages')
          .get();
      expect(messages.docs, isEmpty);
    });

    test('rejects empty text without an image', () async {
      final messaging = FirebaseMessagingService(firestore: firestore);

      await expectLater(
        messaging.sendMessage(
          bookingId: 'b-1',
          senderId: 'seeker-1',
          text: '   ',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects messaging on a booking that does not exist', () async {
      final messaging = FirebaseMessagingService(firestore: firestore);

      await expectLater(
        messaging.sendMessage(
          bookingId: 'missing',
          senderId: 'seeker-1',
          text: 'hi',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('MessageModel.toMap omits null imageUrl', () {
      final message = MessageModel(
        id: 'm-1',
        bookingId: 'b-1',
        senderId: 'seeker-1',
        receiverId: 'provider-1',
        text: 'hello',
        timestamp: DateTime(2026, 1, 1),
      );
      expect(message.toMap().containsKey('imageUrl'), isFalse);
    });
  });
}
