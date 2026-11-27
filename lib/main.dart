import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'src/app.dart';
import 'src/services/account_deletion_service.dart';
import 'src/services/auth_email_service.dart';
import 'src/services/auth_service.dart';
import 'src/services/booking_service.dart';
import 'src/services/email_verification_service.dart';
import 'src/services/fcm_service.dart';
import 'src/services/messaging_service.dart';
import 'src/services/notification_service.dart';
import 'src/services/review_service.dart';
import 'src/services/service_service.dart';

const String _kEmulatorFlag = 'SANGASO_USE_EMULATORS';
const String _kEmulatorHostOverride = 'SANGASO_EMULATOR_HOST';
const String _kAndroidEmulatorHost = '10.0.2.2';
const String _kLocalHost = 'localhost';
const int _kAuthEmulatorPort = 9099;

// Emulator-only Firebase options. The Auth/Firestore emulators accept fake
// app metadata; the critical part is the demo project id so documents land in
// the same namespace that local-test/seed.js writes to.
const FirebaseOptions _kLocalEmulatorOptions = FirebaseOptions(
  apiKey: 'fake-api-key-for-local-emulators',
  appId: '1:000000000000:android:0000000000000000000000',
  messagingSenderId: '000000000000',
  projectId: 'demo-sangaso-local',
  storageBucket: 'demo-sangaso-local.appspot.com',
);
const int _kFirestoreEmulatorPort = 8080;
const int _kStorageEmulatorPort = 9199;

/// Explicit, OPT-IN Firebase emulator mode.
/// Enabled with `flutter run --dart-define=SANGASO_USE_EMULATORS=true` or by
/// setting the SANGASO_USE_EMULATORS=true environment variable (mobile and
/// desktop targets only). There is NO automatic production fallback:
/// production/backed Firebase is never touched when this flag is unset.
bool get useEmulators {
  const compileTime = bool.fromEnvironment(_kEmulatorFlag);
  if (compileTime || kIsWeb) {
    // The env-var lookup is a dart:io platform API; on web only the
    // compile-time --dart-define switch can enable emulator mode.
    return compileTime;
  }
  return Platform.environment[_kEmulatorFlag] == 'true';
}

/// Firebase SDKs expect a bare host, not a URL. Accept either form from the
/// override so `--dart-define=SANGASO_EMULATOR_HOST=http://10.0.2.2` and a
/// plain `10.0.2.2` both work.
String _normaliseEmulatorHost(String value) {
  var candidate = value.trim();
  if (candidate.isEmpty) return '';
  if (!candidate.contains('://')) candidate = 'http://$candidate';
  final uri = Uri.tryParse(candidate);
  final host = uri?.host ?? '';
  return host.isEmpty ? candidate.replaceAll(RegExp(r'^https?://'), '') : host;
}

/// Resolves the emulator host only when emulator mode is explicitly enabled.
/// Android runs the emulator on the Windows host, so `localhost` inside the
/// AVD would point at the device itself. Desktop/web keep `localhost`.
String get emulatorHost {
  const compileTimeOverride = String.fromEnvironment(
    _kEmulatorHostOverride,
    defaultValue: '',
  );
  final override = kIsWeb
      ? compileTimeOverride
      : (compileTimeOverride.isNotEmpty
          ? compileTimeOverride
          : Platform.environment[_kEmulatorHostOverride] ?? '');
  final normalised = _normaliseEmulatorHost(override);
  if (normalised.isNotEmpty) return normalised;
  if (!kIsWeb && Platform.isAndroid) return _kAndroidEmulatorHost;
  return _kLocalHost;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: useEmulators ? _kLocalEmulatorOptions : DefaultFirebaseOptions.currentPlatform,
  );

  // FCM background handler must be registered before runApp so background
  // deliveries (data-only, sent by the trusted backend) have a handler.
  FirebaseMessaging.onBackgroundMessage(fcmBackgroundHandler);

  if (useEmulators) {
    // Host resolution is intentionally scoped to the opt-in branch. With the
    // flag unset the app continues to use the normal Firebase configuration.
    final host = emulatorHost;
    // The host is explicit (AVD 10.0.2.2 or physical-device USB reverse
    // 127.0.0.1). Disable FlutterFire's Android-only loopback remapping so a
    // physical device does not silently redirect 127.0.0.1 to 10.0.2.2.
    await FirebaseAuth.instance.useAuthEmulator(
      host,
      _kAuthEmulatorPort,
      automaticHostMapping: false,
    );
    FirebaseFirestore.instance.useFirestoreEmulator(
      host,
      _kFirestoreEmulatorPort,
      automaticHostMapping: false,
    );
    FirebaseStorage.instance.useStorageEmulator(
      host,
      _kStorageEmulatorPort,
      automaticHostMapping: false,
    );
  }

  // Branded authentication-email client. Present in every build, but the
  // custom transport is only ACTIVE when the build sets
  // SANGASO_AUTH_MAIL_CUSTOM=1 (and the website backend is deployed and
  // configured). Until then Firebase's default sender remains in charge.
  final authEmailService = AuthEmailService(
    transport: HttpAuthEmailTransport(),
  );

  final authService = FirebaseAuthService(authEmailService: authEmailService);
  final notificationService = FirebaseNotificationService();
  final bookingService = FirebaseBookingService(notificationService: notificationService);
  final messagingService = FirebaseMessagingService(notificationService: notificationService);
  final reviewService = FirebaseReviewService();
  final serviceService = ServiceService();
  final emailVerificationService = FirebaseAuthEmailVerificationService(
    authEmailService: authEmailService,
  );
  final accountDeletionService = AccountDeletionService();
  final fcmService = FcmService();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>.value(value: authService),
        Provider<BookingService>.value(value: bookingService),
        Provider<MessagingService>.value(value: messagingService),
        Provider<ReviewService>(create: (_) => reviewService),
        Provider<ServiceService>(create: (_) => serviceService),
        Provider<NotificationService>.value(value: notificationService),
        Provider<EmailVerificationService>.value(value: emailVerificationService),
        Provider<AccountDeletionService>.value(value: accountDeletionService),
        Provider<FcmService>.value(value: fcmService),
        Provider<AuthEmailService>.value(value: authEmailService),
      ],
      child: SangasoApp(
        authService: authService,
        bookingService: bookingService,
        messagingService: messagingService,
        reviewService: reviewService,
        serviceService: serviceService,
        fcmService: fcmService,
      ),
    ),
  );
}
