'use strict';

// Prints a sanitised snapshot of the LOCAL Firestore emulator documents used
// by the Android QA workflows. No credentials, tokens, or production access.
const fs = require('fs');
const path = require('path');

const PROJECT = 'demo-sangaso-local';

function assertLocalHttpEndpoint(raw, label) {
  const value = String(raw || '').trim();
  const url = new URL(value.includes('://') ? value : `http://${value}`);
  if (url.protocol !== 'http:' || !['localhost', '127.0.0.1', '::1'].includes(url.hostname)) {
    throw new Error(`${label} must be a loopback http endpoint`);
  }
  return url;
}

const base = assertLocalHttpEndpoint(
  process.env.SANGASO_FIRESTORE_EMULATOR_HOST || 'http://127.0.0.1:8080',
  'Firestore emulator host',
).origin;

async function list(collection) {
  const response = await fetch(
    `${base}/v1/projects/${PROJECT}/databases/(default)/documents/${collection}?pageSize=100`,
  );
  if (!response.ok) {
    throw new Error(`${collection}: ${response.status} ${await response.text()}`);
  }
  return (await response.json()).documents || [];
}

function decode(value) {
  if (!value || typeof value !== 'object') return null;
  if ('stringValue' in value) return value.stringValue;
  if ('booleanValue' in value) return value.booleanValue;
  if ('integerValue' in value) return Number(value.integerValue);
  if ('doubleValue' in value) return value.doubleValue;
  if ('nullValue' in value) return null;
  if ('timestampValue' in value) return value.timestampValue;
  if ('arrayValue' in value) return (value.arrayValue.values || []).map(decode);
  if ('mapValue' in value) {
    return Object.fromEntries(
      Object.entries(value.mapValue.fields || {}).map(([key, item]) => [key, decode(item)]),
    );
  }
  return value;
}

function plain(doc) {
  const id = doc.name.split('/').pop();
  return { id, ...Object.fromEntries(
    Object.entries(doc.fields || {}).map(([key, value]) => [key, decode(value)]),
  ) };
}

function byId(docs, id) {
  return docs.find((doc) => doc.id === id) || null;
}

async function main() {
  const statePath = path.join(__dirname, 'seed-state.json');
  if (!fs.existsSync(statePath)) {
    throw new Error('Missing seed-state.json; run node seed.js first');
  }
  const state = JSON.parse(fs.readFileSync(statePath, 'utf8'));
  if (state.project !== PROJECT) {
    throw new Error('seed-state.json is not for demo-sangaso-local');
  }

  const [userDocs, serviceDocs, bookingDocs, notificationDocs] = await Promise.all([
    list('users'),
    list('services'),
    list('bookings'),
    list('notifications'),
  ]);
  const users = userDocs.map(plain);
  const services = serviceDocs.map(plain);
  const bookings = bookingDocs.map(plain);
  const notifications = notificationDocs.map(plain);
  const ids = new Set([state.seekerUid, state.providerUid]);

  const snapshot = {
    project: PROJECT,
    capturedAt: new Date().toISOString(),
    seekerUid: state.seekerUid,
    providerUid: state.providerUid,
    seeker: byId(users, state.seekerUid),
    provider: byId(users, state.providerUid),
    services: services.filter((doc) => doc.providerId === state.providerUid),
    bookings: bookings.filter(
      (doc) => ids.has(doc.seekerId) || ids.has(doc.providerId),
    ),
    notifications: notifications.filter((doc) => ids.has(doc.userId)),
    counts: {
      users: users.length,
      services: services.length,
      relatedBookings: bookings.filter(
        (doc) => ids.has(doc.seekerId) || ids.has(doc.providerId),
      ).length,
      relatedNotifications: notifications.filter((doc) => ids.has(doc.userId)).length,
    },
  };

  const output = process.argv[2];
  const text = `${JSON.stringify(snapshot, null, 2)}\n`;
  if (output) {
    fs.writeFileSync(output, text);
    console.log(`Wrote ${output}`);
  } else {
    process.stdout.write(text);
  }
}

main().catch((error) => {
  console.error('Verify failed:', error && error.message ? error.message : error);
  process.exit(1);
});
