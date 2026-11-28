import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sangaso/src/models/public_profile_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fromDoc uses the document id and parses server timestamps', () async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('publicProfiles').doc('provider-1').set({
      'role': 'provider',
      'tradingName': 'Dave Plumbing',
      'bio': 'Local test provider',
      'basePrice': 250,
      'kycApproved': true,
      'isBanned': false,
      'isSuspended': false,
      'updatedAt': Timestamp.fromDate(DateTime(2026, 1, 2)),
    });

    final doc = await firestore.collection('publicProfiles').doc('provider-1').get();
    final profile = PublicProfileModel.fromDoc(doc);

    expect(profile.id, 'provider-1');
    expect(profile.tradingName, 'Dave Plumbing');
    expect(profile.bio, 'Local test provider');
    expect(profile.basePrice, 250);
    expect(profile.isDiscoverable, isTrue);
    expect(profile.updatedAt, DateTime(2026, 1, 2));
  });

  test('moderated profiles are not discoverable', () {
    final profile = PublicProfileModel.fromMap({
      'role': 'provider',
      'kycApproved': true,
      'isSuspended': true,
    }, fallbackId: 'provider-2');

    expect(profile.id, 'provider-2');
    expect(profile.isDiscoverable, isFalse);
  });
}
