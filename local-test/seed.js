'use strict';

// Deterministic seed for the LOCAL Firebase emulators only.
// Project is hard-pinned to demo-sangaso-local; endpoints are restricted to
// loopback addresses. No production project or credential can be used here.
const fs = require('fs');
const path = require('path');

const PROJECT = 'demo-sangaso-local';
const ALLOWED_DOMAIN = '@demo-sangaso-local.test';
const CREDENTIALS_FILE =
  process.env.SANGASO_FAKE_CREDENTIALS_FILE ||
  path.join(__dirname, 'fake-credentials.local.json');

function assertLocalHttpEndpoint(raw, label) {
  const value = String(raw || '').trim();
  const url = new URL(value.includes('://') ? value : `http://${value}`);
  if (url.protocol !== 'http:') {
    throw new Error(`${label} must use http (local emulator only)`);
  }
  if (!['localhost', '127.0.0.1', '::1'].includes(url.hostname)) {
    throw new Error(`${label} must stay on localhost/127.0.0.1/::1`);
  }
  return url;
}

const authEndpoint = assertLocalHttpEndpoint(
  process.env.SANGASO_AUTH_EMULATOR_HOST || 'http://127.0.0.1:9099',
  'Auth emulator host',
);
const firestoreEndpoint = assertLocalHttpEndpoint(
  process.env.SANGASO_FIRESTORE_EMULATOR_HOST || 'http://127.0.0.1:8080',
  'Firestore emulator host',
);

const authBase = authEndpoint.origin;
const firestoreBase = firestoreEndpoint.origin;

// firebase-admin reads this variable before initializeApp and routes all Auth
// calls to the emulator. Never set GOOGLE_APPLICATION_CREDENTIALS here.
process.env.FIREBASE_AUTH_EMULATOR_HOST =
  authEndpoint.hostname === '::1'
    ? `[::1]:${authEndpoint.port || 9099}`
    : `${authEndpoint.hostname}:${authEndpoint.port || 9099}`;

const { initializeApp, getApps } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');

if (!getApps().length) {
  initializeApp({ projectId: PROJECT });
}
const auth = getAuth();

const str = (value) => ({ stringValue: value });
const bool = (value) => ({ booleanValue: value });
const int = (value) => ({ integerValue: String(value) });
const ts = (iso) => ({ stringValue: iso });

const docPath = (collection, id) =>
  `v1/projects/${PROJECT}/databases/(default)/documents/${collection}/${encodeURIComponent(id)}`;
const collectionPath = (collection) =>
  `v1/projects/${PROJECT}/databases/(default)/documents/${collection}`;

function loadCredentials() {
  if (!fs.existsSync(CREDENTIALS_FILE)) {
    throw new Error(
      `Missing local fake credentials: ${CREDENTIALS_FILE}. Create it outside Git; see local-test/README.md.`,
    );
  }
  const credentials = JSON.parse(fs.readFileSync(CREDENTIALS_FILE, 'utf8'));
  for (const role of ['seeker', 'provider']) {
    const item = credentials[role];
    if (!item || typeof item.email !== 'string' || typeof item.password !== 'string') {
      throw new Error(`Credentials file must define ${role}.email and ${role}.password`);
    }
    if (!item.email.trim().toLowerCase().endsWith(ALLOWED_DOMAIN)) {
      throw new Error(`${role}.email must use ${ALLOWED_DOMAIN} only`);
    }
    if (item.password.length < 8) {
      throw new Error(`${role}.password must be at least 8 characters`);
    }
  }
  if (
    credentials.seeker.email.trim().toLowerCase() ===
    credentials.provider.email.trim().toLowerCase()
  ) {
    throw new Error('Seeker and provider test emails must differ');
  }
  return credentials;
}

async function upsertAuthUser(role, credentials, profile) {
  const email = credentials.email.trim().toLowerCase();
  const password = credentials.password;

  let existing;
  try {
    existing = await auth.getUserByEmail(email);
  } catch (error) {
    if (error && error.code === 'auth/user-not-found') {
      existing = null;
    } else {
      throw error;
    }
  }

  let uid;
  if (existing) {
    uid = existing.uid;
    await auth.updateUser(uid, {
      email,
      password,
      emailVerified: true,
      displayName: profile.displayName,
    });
  } else {
    const created = await auth.createUser({
      email,
      password,
      emailVerified: true,
      displayName: profile.displayName,
    });
    uid = created.uid;
  }

  const fresh = await auth.getUser(uid);
  if (!fresh.emailVerified) {
    throw new Error(`Auth EMULATOR user ${role} is not emailVerified`);
  }
  return { uid, email, role, profile };
}

async function verifyPasswordSignIn(user) {
  const response = await fetch(
    `${authBase}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-api-key`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: user.email,
        password: user.credentials.password,
        returnSecureToken: true,
      }),
    },
  );
  if (!response.ok) {
    throw new Error(`Password verification failed for ${user.role}: ${response.status}`);
  }
  const body = await response.json();
  if (body.localId !== user.uid) {
    throw new Error(`Password verification UID mismatch for ${user.role}`);
  }
}

async function patchDocument(collection, id, fields) {
  const response = await fetch(`${firestoreBase}/${docPath(collection, id)}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ fields }),
  });
  if (!response.ok) {
    throw new Error(`${collection}/${id}: ${response.status} ${await response.text()}`);
  }
  return response.json();
}

async function listDocuments(collection) {
  const response = await fetch(`${firestoreBase}/${collectionPath(collection)}?pageSize=100`);
  if (!response.ok) {
    throw new Error(`list ${collection}: ${response.status} ${await response.text()}`);
  }
  return response.json();
}

function userFields(user) {
  const fields = {
    id: str(user.uid),
    email: str(user.email),
    role: str(user.role),
    isVerified: bool(true),
    displayName: str(user.profile.displayName),
    phoneNumber: str(user.profile.phoneNumber),
    city: str(user.profile.city),
    address: str(user.profile.address),
    isBanned: bool(false),
    isSuspended: bool(false),
    createdAt: ts('2026-01-01T00:00:00Z'),
    updatedAt: ts('2026-01-01T00:00:00Z'),
  };
  if (user.role === 'provider') {
    fields.tradingName = str('Sangaso Demo Provider');
    fields.category = str('Cleaning');
    fields.bio = str('Local emulator provider for end-to-end QA.');
    fields.basePrice = { doubleValue: 250 };
    fields.heardAbout = str('local-test seed');
  }
  return fields;
}

const serviceSpecs = [
  {
    id: 'svc-clean-001',
    name: 'Deep apartment clean',
    description: 'Full apartment clean with supplies',
    category: 'Cleaning',
    price: 250,
  },
  {
    id: 'svc-plumb-001',
    name: 'Bathroom plumbing repair',
    description: 'Leaking taps and pipes',
    category: 'Plumbing',
    price: 180,
  },
  {
    id: 'svc-elec-001',
    name: 'Ceiling fan installation',
    description: 'Ceiling fan install small job',
    category: 'Electrical',
    price: 150,
  },
];

function serviceFields(spec, providerUid) {
  return {
    id: str(spec.id),
    providerId: str(providerUid),
    name: str(spec.name),
    description: str(spec.description),
    category: str(spec.category),
    price: { doubleValue: spec.price },
    imageUrls: { arrayValue: { values: [] } },
    isActive: bool(true),
    createdAt: ts('2026-01-01T00:00:00Z'),
    updatedAt: ts('2026-01-01T00:00:00Z'),
  };
}

async function main() {
  const credentials = loadCredentials();

  const seeker = await upsertAuthUser('seeker', credentials.seeker, {
    displayName: 'Demo Seeker',
    phoneNumber: '+15550000001',
    city: 'Local Test City',
    address: '1 Seeker Lane',
  });
  seeker.credentials = credentials.seeker;
  const provider = await upsertAuthUser('provider', credentials.provider, {
    displayName: 'Demo Provider',
    phoneNumber: '+15550000002',
    city: 'Local Test City',
    address: '2 Provider Lane',
  });
  provider.credentials = credentials.provider;

  await verifyPasswordSignIn(seeker);
  await verifyPasswordSignIn(provider);

  for (const user of [seeker, provider]) {
    const doc = await patchDocument('users', user.uid, userFields(user));
    console.log(`Firestore seeded users/${user.uid} role=${user.role} (${doc.name})`);
  }

  for (const spec of serviceSpecs) {
    const doc = await patchDocument(
      'services',
      spec.id,
      serviceFields(spec, provider.uid),
    );
    console.log(`Firestore seeded services/${spec.id} providerUid=${provider.uid} (${doc.name})`);
  }

  const serviceCheck = await listDocuments('services');
  const services = serviceCheck.documents || [];
  if (services.length !== serviceSpecs.length) {
    throw new Error(`Expected ${serviceSpecs.length} service docs, found ${services.length}`);
  }
  for (const doc of services) {
    const fields = doc.fields || {};
    if (fields.providerId?.stringValue !== provider.uid) {
      throw new Error(`Service ${doc.name} has a providerId that is not the seeded provider UID`);
    }
  }

  const userCheck = await listDocuments('users');
  const users = userCheck.documents || [];
  const seededUids = new Set([seeker.uid, provider.uid]);
  for (const doc of users) {
    if (!seededUids.has(doc.name.split('/').pop())) {
      throw new Error(`Unexpected user document in local emulator: ${doc.name}`);
    }
    if ((doc.fields || {}).isVerified?.booleanValue !== true) {
      throw new Error(`User document is not verified: ${doc.name}`);
    }
  }

  fs.writeFileSync(
    path.join(__dirname, 'seed-state.json'),
    `${JSON.stringify(
      {
        project: PROJECT,
        seekerUid: seeker.uid,
        providerUid: provider.uid,
        seekerEmail: seeker.email,
        providerEmail: provider.email,
        generatedAt: new Date().toISOString(),
      },
      null,
      2,
    )}\n`,
  );

  console.log('Auth EMULATOR users verified with emailVerified=true and working passwords.');
  console.log(`Seed verification PASS: ${users.length} users, ${services.length} services.`);
  console.log(`SEEKER_UID=${seeker.uid}`);
  console.log(`PROVIDER_UID=${provider.uid}`);
}

main().catch((error) => {
  console.error('Seed failed:', error && error.message ? error.message : error);
  process.exit(1);
});
