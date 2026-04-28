import { getDb } from "@/lib/localDb";

const DEFAULT_PRIVACY_SETTINGS = {
  privacyEnabled: false,
  anonymizeIps: true,
  anonymizeEmails: true,
  anonymizeHashes: true,
  anonymizeApiKeys: true,
  anonymizeHostnames: true,
  anonymizeCustom: []
};

export async function getPrivacySettings() {
  const db = await getDb();
  if (!db.data.privacySettings) {
    db.data.privacySettings = { ...DEFAULT_PRIVACY_SETTINGS };
  }
  return db.data.privacySettings;
}

export async function updatePrivacySettings(updates) {
  const db = await getDb();
  db.data.privacySettings = { ...db.data.privacySettings, ...updates };
  await db.write();
  return db.data.privacySettings;
}
