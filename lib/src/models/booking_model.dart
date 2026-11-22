import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_date.dart';

enum BookingStatus {
  requested,
  accepted,
  declined,
  inProgress,
  completed,
  cancelled,
}

class BookingModel {
  final String id;
  final String seekerId;
  final String providerId;
  final String serviceType;
  final DateTime scheduledTime;
  final String address;
  final double price;
  final BookingStatus status;
  final DateTime createdAt;

  // Denormalized seeker information for quick access
  final String? seekerName;
  final String? seekerPhone;
  final String? seekerEmail;

  // Denormalized provider information for quick access
  final String? providerName;
  final String? providerPhone;
  final String? providerEmail;

  // Additional booking details
  final String? specialInstructions;

  // Status tracking
  final DateTime? acceptedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;

  // Origin service (nullable: legacy bookings predate service references
  // and were created from the provider's profile price).
  final String? serviceId;
  final String? serviceName;

  BookingModel({
    required this.id,
    required this.seekerId,
    required this.providerId,
    required this.serviceType,
    required this.scheduledTime,
    required this.address,
    required this.price,
    required this.status,
    required this.createdAt,
    this.seekerName,
    this.seekerPhone,
    this.seekerEmail,
    this.providerName,
    this.providerPhone,
    this.providerEmail,
    this.specialInstructions,
    this.acceptedAt,
    this.startedAt,
    this.completedAt,
    this.serviceId,
    this.serviceName,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'seekerId': seekerId,
      'providerId': providerId,
      'serviceType': serviceType,
      'scheduledTime': Timestamp.fromDate(scheduledTime),
      'address': address,
      'price': price,
      'status': status.name,
      'createdAt': Timestamp.fromDate(createdAt),
      'seekerName': seekerName,
      'seekerPhone': seekerPhone,
      'seekerEmail': seekerEmail,
      'providerName': providerName,
      'providerPhone': providerPhone,
      'providerEmail': providerEmail,
      'specialInstructions': specialInstructions,
      // The website reads the free-text note from `notes`; keep both fields
      // in sync so a booking created on either client is readable on both.
      'notes': specialInstructions,
      'acceptedAt': acceptedAt != null ? Timestamp.fromDate(acceptedAt!) : null,
      'startedAt': startedAt != null ? Timestamp.fromDate(startedAt!) : null,
      'completedAt': completedAt != null
          ? Timestamp.fromDate(completedAt!)
          : null,
      'serviceId': serviceId,
      'serviceName': serviceName,
    };
  }

  factory BookingModel.fromMap(Map<String, dynamic> map) {
    return BookingModel(
      id: map['id'] ?? '',
      seekerId: map['seekerId'] ?? '',
      providerId: map['providerId'] ?? '',
      serviceType: map['serviceType'] ?? map['serviceName'] ?? '',
      scheduledTime: parseFirestoreDate(map['scheduledTime'], field: 'scheduledTime'),
      address: map['address'] ?? '',
      price: (map['price'] as num?)?.toDouble() ?? 0,
      status: BookingStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => BookingStatus.requested,
      ),
      createdAt: parseFirestoreDate(map['createdAt'], field: 'createdAt'),
      seekerName: map['seekerName'],
      seekerPhone: map['seekerPhone'],
      seekerEmail: map['seekerEmail'],
      providerName: map['providerName'],
      providerPhone: map['providerPhone'],
      providerEmail: map['providerEmail'],
      // Website bookings store the note as `notes`; Android bookings use
      // `specialInstructions`. Read either.
      specialInstructions: map['specialInstructions'] ?? map['notes'],
      acceptedAt: parseFirestoreDateOrNull(map['acceptedAt'], field: 'acceptedAt'),
      startedAt: parseFirestoreDateOrNull(map['startedAt'], field: 'startedAt'),
      completedAt: parseFirestoreDateOrNull(map['completedAt'], field: 'completedAt'),
      serviceId: map['serviceId'],
      serviceName: map['serviceName'],
    );
  }

  /// Builds a booking from a Firestore document, falling back to the
  /// document ID when the payload has no usable `id` field.
  ///
  /// Website-created bookings use an auto-generated document ID and do not
  /// store `id` inside the payload, so this fallback keeps IDs stable across
  /// both clients (and prevents empty-ID display/cancellation problems).
  factory BookingModel.fromDoc(DocumentSnapshot<Object?> doc) {
    final raw = doc.data();
    final data = raw is Map<String, dynamic> ? raw : <String, dynamic>{};
    final storedId = data['id'];
    return BookingModel.fromMap({
      ...data,
      'id': storedId is String && storedId.isNotEmpty ? storedId : doc.id,
    });
  }
}
