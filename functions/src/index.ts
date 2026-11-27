import * as admin from 'firebase-admin';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import {
  onDocumentCreated,
  onDocumentUpdated,
  onDocumentWritten,
} from 'firebase-functions/v2/firestore';

admin.initializeApp();

const db = admin.firestore();

type UserPatch = {
  uid?: unknown;
  role?: unknown;
  isAdmin?: unknown;
  isVerified?: unknown;
  kycApproved?: unknown;
  isBanned?: unknown;
  isSuspended?: unknown;
};

const ALLOWED_ROLES = ['seeker', 'provider', 'admin'] as const;
const ALLOWED_PATCH_KEYS = new Set([
  'role',
  'isAdmin',
  'isVerified',
  'kycApproved',
  'isBanned',
  'isSuspended',
]);

function requireAdmin(uid: string | undefined): Promise<admin.auth.UserRecord> {
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Sign-in is required.');
  }
  return admin.auth().getUser(uid).then((caller) => {
    if (caller.customClaims?.admin !== true) {
      throw new HttpsError('permission-denied', 'Admin claim required.');
    }
    return caller;
  });
}

function notificationPayload(input: {
  userId: string;
  title: string;
  message: string;
  type: string;
  relatedId: string;
}) {
  return {
    userId: input.userId,
    title: input.title,
    message: input.message,
    body: input.message,
    type: input.type,
    relatedId: input.relatedId,
    isRead: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

/**
 * Admin-only claim and moderation writer.
 *
 * This is the only supported way to grant/revoke the `admin` claim or change
 * KYC/ban/suspension state. Firestore rules check `request.auth.token.admin`,
 * never a user-document field.
 */
export const setUserClaims = onCall(async (request): Promise<{ ok: true }> => {
  await requireAdmin(request.auth?.uid);

  const patch = (request.data ?? {}) as UserPatch;
  const keys = Object.keys(patch).filter((key) => key !== 'uid');
  if (keys.length === 0) {
    throw new HttpsError('invalid-argument', 'No changes supplied.');
  }
  for (const key of keys) {
    if (!ALLOWED_PATCH_KEYS.has(key)) {
      throw new HttpsError('invalid-argument', `Unsupported field: ${key}`);
    }
  }

  const uid = typeof patch.uid === 'string' ? patch.uid.trim() : '';
  if (!uid || uid.length > 128) {
    throw new HttpsError('invalid-argument', 'A valid uid is required.');
  }

  const target = await admin.auth().getUser(uid);
  const claims: Record<string, unknown> = { ...(target.customClaims ?? {}) };
  const userUpdate: Record<string, unknown> = {
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  if ('role' in patch) {
    if (typeof patch.role !== 'string' || !ALLOWED_ROLES.includes(patch.role as (typeof ALLOWED_ROLES)[number])) {
      throw new HttpsError('invalid-argument', 'Invalid role.');
    }
    claims.role = patch.role;
    userUpdate.role = patch.role;
  }
  if ('isAdmin' in patch) {
    if (typeof patch.isAdmin !== 'boolean') {
      throw new HttpsError('invalid-argument', 'isAdmin must be a boolean.');
    }
    claims.admin = patch.isAdmin;
  }
  for (const key of ['isVerified', 'kycApproved', 'isBanned', 'isSuspended'] as const) {
    if (key in patch) {
      if (typeof patch[key] !== 'boolean') {
        throw new HttpsError('invalid-argument', `${key} must be a boolean.`);
      }
      userUpdate[key] = patch[key];
    }
  }

  await admin.auth().setCustomUserClaims(uid, claims);
  await db.collection('users').doc(uid).set(userUpdate, { merge: true });
  return { ok: true };
});

/** Maintains a non-PII public projection for provider/seeker discovery. */
export const syncPublicProfile = onDocumentWritten('users/{uid}', async (event) => {
  const uid = event.params.uid;
  const after = event.data?.after;
  const profileRef = db.collection('publicProfiles').doc(uid);

  if (!after?.exists) {
    await profileRef.delete();
    return;
  }

  const data = after.data();
  if (!data) {
    return;
  }
  await profileRef.set(
    {
      role: data.role ?? 'seeker',
      displayName: data.displayName ?? null,
      tradingName: data.tradingName ?? null,
      category: data.category ?? null,
      city: data.city ?? null,
      photoUrl: data.photoUrl ?? null,
      basePrice: data.basePrice ?? null,
      kycApproved: data.kycApproved === true,
      isBanned: data.isBanned === true,
      isSuspended: data.isSuspended === true,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
});

/** Backend-owned notification for a newly requested booking. */
export const onBookingCreated = onDocumentCreated('bookings/{bookingId}', async (event) => {
  const snapshot = event.data;
  if (!snapshot) return;
  const booking = snapshot.data();
  if (!booking.providerId) return;

  await db.collection('notifications').add(
    notificationPayload({
      userId: booking.providerId,
      title: 'New Booking Request',
      message: `You have a new request for ${booking.serviceType ?? 'a service'} service.`,
      type: 'bookingRequest',
      relatedId: event.params.bookingId,
    }),
  );
});

/** Backend-owned notifications for booking lifecycle transitions. */
export const onBookingStatusChanged = onDocumentUpdated('bookings/{bookingId}', async (event) => {
  const change = event.data;
  if (!change) return;
  const before = change.before.data();
  const after = change.after.data();
  if (before.status === after.status) return;

  const bookingId = event.params.bookingId;
  let payload: ReturnType<typeof notificationPayload> | null = null;

  switch (after.status) {
    case 'accepted':
      payload = notificationPayload({
        userId: after.seekerId,
        title: 'Booking Accepted',
        message: `${after.providerName ?? 'Provider'} has accepted your booking.`,
        type: 'bookingAccepted',
        relatedId: bookingId,
      });
      break;
    case 'declined':
      payload = notificationPayload({
        userId: after.seekerId,
        title: 'Booking Declined',
        message: `${after.providerName ?? 'Provider'} has declined your booking.`,
        type: 'bookingDeclined',
        relatedId: bookingId,
      });
      break;
    case 'inProgress':
      payload = notificationPayload({
        userId: after.seekerId,
        title: 'Job Started',
        message: `${after.providerName ?? 'Provider'} has started the job.`,
        type: 'jobStarted',
        relatedId: bookingId,
      });
      break;
    case 'completed':
      payload = notificationPayload({
        userId: after.seekerId,
        title: 'Job Completed',
        message: 'Your service has been completed. Please leave a review!',
        type: 'jobCompleted',
        relatedId: bookingId,
      });
      break;
    case 'cancelled':
      payload = notificationPayload({
        userId: after.providerId,
        title: 'Booking Cancelled',
        message: `${after.seekerName ?? 'Customer'} has cancelled the booking.`,
        type: 'bookingCancelled',
        relatedId: bookingId,
      });
      break;
    default:
      return;
  }

  await db.collection('notifications').add(payload);
});

/** Backend-owned recipient notification for chat messages. */
export const onMessageCreated = onDocumentCreated(
  'bookings/{bookingId}/messages/{messageId}',
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;
    const message = snapshot.data();
    if (!message.receiverId || !message.text) return;

    await db.collection('notifications').add(
      notificationPayload({
        userId: message.receiverId,
        title: 'New Message',
        message: message.text.slice(0, 300),
        type: 'message',
        relatedId: event.params.bookingId,
      }),
    );
  },
);

/** Backend-owned provider notification for a new review. */
export const onReviewCreated = onDocumentCreated('reviews/{reviewId}', async (event) => {
  const snapshot = event.data;
  if (!snapshot) return;
  const review = snapshot.data();
  if (!review.providerId) return;

  await db.collection('notifications').add(
    notificationPayload({
      userId: review.providerId,
      title: 'New Review',
      message: `${review.seekerName ?? 'A customer'} gave you ${review.rating} star(s).`,
      type: 'newReview',
      relatedId: review.bookingId ?? event.params.reviewId,
    }),
  );
});
