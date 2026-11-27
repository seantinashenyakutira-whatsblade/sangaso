const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { Timestamp } = require('firebase/firestore');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');

const PROJECT_ID = 'demo-sangaso-rules';
const rules = fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8');

let env;

async function seed(fn) {
  await env.withSecurityRulesDisabled(async (context) => {
    await fn(context.firestore());
  });
}

function userDoc(uid, role = 'seeker', email = `${uid}@example.com`) {
  return {
    id: uid,
    email,
    role,
    isVerified: true,
    isBanned: false,
    isSuspended: false,
    kycApproved: role === 'provider',
    displayName: uid,
    createdAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
  };
}

function bookingDoc(id, seekerId, providerId, status = 'requested') {
  const now = Timestamp.now();
  return {
    id,
    seekerId,
    providerId,
    serviceType: 'Cleaning',
    scheduledTime: Timestamp.fromMillis(Date.now() + 86400000),
    address: 'Lusaka',
    price: 100,
    status,
    seekerEmail: `${seekerId}@example.com`,
    providerEmail: `${providerId}@example.com`,
    createdAt: now,
    updatedAt: now,
  };
}

test.before(async () => {
  env = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules,
      host: '127.0.0.1',
      port: Number(process.env.FIRESTORE_EMULATOR_PORT || 8080),
    },
  });
});

test.beforeEach(async () => {
  await env.clearFirestore();
});

test.after(async () => {
  await env.cleanup();
});

test('unauthenticated client cannot read user documents', async () => {
  await seed((db) => db.collection('users').doc('seeker1').set(userDoc('seeker1')));
  const db = env.unauthenticatedContext().firestore();
  await assertFails(db.collection('users').doc('seeker1').get());
});

test('user cannot read another user document containing PII', async () => {
  await seed(async (db) => {
    await db.collection('users').doc('seeker1').set(userDoc('seeker1'));
    await db.collection('users').doc('seeker2').set(userDoc('seeker2'));
  });
  const db = env.authenticatedContext('seeker1', { email: 'seeker1@example.com' }).firestore();
  await assertFails(db.collection('users').doc('seeker2').get());
});

test('user cannot create a user document with admin role', async () => {
  const db = env.authenticatedContext('attacker', { email: 'attacker@example.com' }).firestore();
  const doc = db.collection('users').doc('attacker');
  await assertFails(doc.set({ ...userDoc('attacker', 'admin'), role: 'admin' }));
});

test('user cannot escalate role via update', async () => {
  await seed((db) => db.collection('users').doc('seeker1').set(userDoc('seeker1')));
  const db = env.authenticatedContext('seeker1', { email: 'seeker1@example.com' }).firestore();
  await assertFails(db.collection('users').doc('seeker1').update({ role: 'admin' }));
});

test('provider cannot take over another provider service', async () => {
  await seed(async (db) => {
    await db.collection('users').doc('provider1').set(userDoc('provider1', 'provider'));
    await db.collection('users').doc('provider2').set(userDoc('provider2', 'provider'));
    await db.collection('services').doc('service1').set({
      id: 'service1',
      providerId: 'provider1',
      name: 'Cleaning',
      category: 'cleaning',
      price: 100,
      isActive: true,
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
    });
  });
  const db = env.authenticatedContext('provider2', { email: 'provider2@example.com' }).firestore();
  await assertFails(db.collection('services').doc('service1').update({ providerId: 'provider2' }));
});

test('non-participant cannot read a booking', async () => {
  await seed(async (db) => {
    await db.collection('users').doc('seeker1').set(userDoc('seeker1'));
    await db.collection('users').doc('provider1').set(userDoc('provider1', 'provider'));
    await db.collection('bookings').doc('booking1').set(bookingDoc('booking1', 'seeker1', 'provider1'));
  });
  const db = env.authenticatedContext('outsider', { email: 'outsider@example.com' }).firestore();
  await assertFails(db.collection('bookings').doc('booking1').get());
});

test('seeker cannot force a booking to completed', async () => {
  await seed(async (db) => {
    await db.collection('users').doc('seeker1').set(userDoc('seeker1'));
    await db.collection('users').doc('provider1').set(userDoc('provider1', 'provider'));
    await db.collection('bookings').doc('booking1').set(bookingDoc('booking1', 'seeker1', 'provider1'));
  });
  const db = env.authenticatedContext('seeker1', { email: 'seeker1@example.com' }).firestore();
  await assertFails(db.collection('bookings').doc('booking1').update({ status: 'completed' }));
});

test('client cannot create notifications', async () => {
  const db = env.authenticatedContext('attacker', { email: 'attacker@example.com' }).firestore();
  await assertFails(db.collection('notifications').doc('fake').set({
    userId: 'victim',
    title: 'Fake',
    message: 'Spoofed',
    type: 'bookingAccepted',
    createdAt: Timestamp.now(),
  }));
});

test('non-participant cannot read booking chat', async () => {
  await seed(async (db) => {
    await db.collection('users').doc('seeker1').set(userDoc('seeker1'));
    await db.collection('users').doc('provider1').set(userDoc('provider1', 'provider'));
    await db.collection('bookings').doc('booking1').set(bookingDoc('booking1', 'seeker1', 'provider1'));
    await db.collection('bookings').doc('booking1').collection('messages').doc('m1').set({
      bookingId: 'booking1',
      senderId: 'seeker1',
      receiverId: 'provider1',
      text: 'Private',
      timestamp: Timestamp.now(),
      isRead: false,
    });
  });
  const db = env.authenticatedContext('outsider', { email: 'outsider@example.com' }).firestore();
  await assertFails(db.collection('bookings').doc('booking1').collection('messages').doc('m1').get());
});

test('oversized user bio is rejected on update', async () => {
  await seed((db) => db.collection('users').doc('seeker1').set(userDoc('seeker1')));
  const db = env.authenticatedContext('seeker1', { email: 'seeker1@example.com' }).firestore();
  await assertFails(
    db.collection('users').doc('seeker1').update({ bio: 'x'.repeat(5000) }),
  );
});

test('admin claim holder can moderate a user', async () => {
  await seed((db) => db.collection('users').doc('provider1').set(userDoc('provider1', 'provider')));
  const db = env.authenticatedContext('admin1', { admin: true, email: 'admin@example.com' }).firestore();
  await assertSucceeds(
    db.collection('users').doc('provider1').update({ isSuspended: true, kycApproved: false }),
  );
});

test('public profile projection is readable', async () => {
  await seed((db) => db.collection('publicProfiles').doc('provider1').set({
    role: 'provider',
    displayName: 'Provider One',
    kycApproved: true,
  }));
  const db = env.unauthenticatedContext().firestore();
  await assertSucceeds(db.collection('publicProfiles').doc('provider1').get());
});
