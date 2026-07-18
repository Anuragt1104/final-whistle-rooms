import crypto from "crypto";

type DeviceRecord = { token: string; platform: string; registeredAt: number; fixtureIds: Set<string> };

declare global {
  // eslint-disable-next-line no-var
  var __fwr_push: {
    devices: Map<string, DeviceRecord>;
    notified: Map<string, number>;
    testNotified: Map<string, number>;
    accessToken: { value: string; expiresAt: number } | null;
  } | undefined;
}

function pushStore() {
  if (!globalThis.__fwr_push) {
    globalThis.__fwr_push = {
      devices: new Map(),
      notified: new Map(),
      testNotified: new Map(),
      accessToken: null,
    };
  }
  globalThis.__fwr_push.testNotified ??= new Map();
  return globalThis.__fwr_push;
}

export function fcmConfigured(): boolean {
  return !!(
    process.env.FCM_PROJECT_ID &&
    process.env.FCM_CLIENT_EMAIL &&
    process.env.FCM_PRIVATE_KEY
  );
}

export function fixtureTopic(fixtureId: string): string {
  return `fixture_${fixtureId.replace(/[^A-Za-z0-9_.~-]/g, "_")}`;
}

export function registerDevice(token: string, platform: string, fixtureIds: string[] = []): void {
  if (!token || token.length < 20) return;
  pushStore().devices.set(token, {
    token,
    platform: platform || "unknown",
    registeredAt: Date.now(),
    fixtureIds: new Set(fixtureIds.filter(Boolean).slice(0, 20)),
  });
}

export function isRegisteredDevice(token: string): boolean {
  return pushStore().devices.has(token);
}

export type GoalPushInput = {
  roomId: string;
  fixtureId: string;
  roomName: string;
  stage?: string;
  homeName: string;
  awayName: string;
  homeGoals: number;
  awayGoals: number;
  minute: number;
  teamName: string;
  scorer: string;
  side: "home" | "away";
  sourceEventId?: string;
};

const TITLES = [
  "⚽ NET BULGES",
  "⚽ THEY'VE SCORED",
  "⚽ GOAL ALERT",
  "⚽ BACK OF THE NET",
  "⚽ IT'S IN",
  "⚽ ABSOLUTE ROCKET",
];

function wittyCopy(g: GoalPushInput): { title: string; body: string } {
  const title = `${TITLES[Math.floor(Math.random() * TITLES.length)]} — ${g.teamName}`;
  const bodies = [
    `${g.scorer} just ruined someone's evening. ${g.homeName} ${g.homeGoals}–${g.awayGoals} ${g.awayName} · ${g.minute}'`,
    `${g.scorer} finds the onion bag! ${g.homeName} ${g.homeGoals}–${g.awayGoals} ${g.awayName} (${g.minute}')`,
    `Cue the chaos — ${g.scorer} puts ${g.teamName} on the scoreboard. ${g.homeGoals}–${g.awayGoals} at ${g.minute}'`,
    `${g.teamName} strike through ${g.scorer}. Scoreboard reads ${g.homeGoals}–${g.awayGoals} · ${g.minute}'`,
    `Hold that thought — ${g.scorer} has spoken. ${g.homeName} ${g.homeGoals}–${g.awayGoals} ${g.awayName}`,
  ];
  return { title, body: bodies[Math.floor(Math.random() * bodies.length)] };
}

function fingerprint(g: GoalPushInput): string {
  return g.sourceEventId || `${g.fixtureId}:${g.homeGoals}-${g.awayGoals}:${g.minute}:${g.side}:${g.scorer}`;
}

/** Fan out a verified goal only to fans watching this Fixture. */
export async function notifyGoal(g: GoalPushInput): Promise<void> {
  if (!fcmConfigured()) return;

  const fp = fingerprint(g);
  const store = pushStore();
  const last = store.notified.get(fp);
  if (last && Date.now() - last < 120_000) return;
  store.notified.set(fp, Date.now());
  // prune old fingerprints
  if (store.notified.size > 500) {
    const cutoff = Date.now() - 3_600_000;
    for (const [k, ts] of store.notified) {
      if (ts < cutoff) store.notified.delete(k);
    }
  }

  const { title, body } = wittyCopy(g);
  const subText = g.stage ? `${g.stage} · ${g.roomName}` : g.roomName;
  const data: Record<string, string> = {
    type: "goal",
    fingerprint: fp,
    roomId: g.roomId,
    fixtureId: g.fixtureId,
    roomName: g.roomName,
    stage: g.stage ?? "",
    homeName: g.homeName,
    awayName: g.awayName,
    homeGoals: String(g.homeGoals),
    awayGoals: String(g.awayGoals),
    minute: String(g.minute),
    teamName: g.teamName,
    scorer: g.scorer,
    side: g.side,
    title,
    body,
    subText,
  };

  try {
    await sendFcm({
      topic: fixtureTopic(g.fixtureId),
      notification: { title, body },
      data,
      android: {
        priority: "HIGH",
        notification: {
          channelId: "match_events",
          sound: "default",
        },
      },
      apns: {
        payload: {
          aps: { sound: "default", badge: 1 },
        },
      },
    });
  } catch (err) {
    console.warn("[push] topic send failed", err);
    // Fallback: multicast to registered tokens
    const tokens = [...store.devices.values()]
      .filter((device) => device.fixtureIds.has(g.fixtureId))
      .map((device) => device.token);
    for (const token of tokens.slice(0, 500)) {
      try {
        await sendFcm({
          token,
          notification: { title, body },
          data,
          android: {
            priority: "HIGH",
            notification: { channelId: "match_events", sound: "default" },
          },
        });
      } catch (e) {
        console.warn("[push] token send failed", e);
      }
    }
  }
}

export async function sendTestNotification(token: string): Promise<{ ok: boolean; error?: string }> {
  const store = pushStore();
  if (!store.devices.has(token)) return { ok: false, error: "device not registered" };
  if (!fcmConfigured()) return { ok: false, error: "FCM not configured" };
  const last = store.testNotified.get(token) ?? 0;
  if (Date.now() - last < 60_000) return { ok: false, error: "try again in one minute" };
  store.testNotified.set(token, Date.now());
  await sendFcm({
    token,
    notification: { title: "Final Whistle alerts are ready", body: "Locked-screen goal alerts are working on this phone." },
    data: { type: "diagnostic", title: "Final Whistle alerts are ready", body: "Locked-screen goal alerts are working on this phone." },
    android: { priority: "HIGH", notification: { channelId: "match_events", sound: "default" } },
  });
  return { ok: true };
}

export type FcmMessage = {
  topic?: string;
  token?: string;
  notification?: { title: string; body: string };
  data?: Record<string, string>;
  android?: Record<string, unknown>;
  apns?: Record<string, unknown>;
};

export async function sendFcm(message: FcmMessage): Promise<void> {
  const projectId = process.env.FCM_PROJECT_ID!;
  const accessToken = await getAccessToken();
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ message }),
    },
  );
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`FCM ${res.status}: ${text}`);
  }
}

async function getAccessToken(): Promise<string> {
  const store = pushStore();
  if (store.accessToken && store.accessToken.expiresAt > Date.now() + 60_000) {
    return store.accessToken.value;
  }

  const clientEmail = process.env.FCM_CLIENT_EMAIL!;
  let privateKey = process.env.FCM_PRIVATE_KEY!;
  // Railway/env often stores newlines as \n
  privateKey = privateKey.replace(/\\n/g, "\n");

  const now = Math.floor(Date.now() / 1000);
  const header = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = base64url(
    JSON.stringify({
      iss: clientEmail,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    }),
  );
  const unsigned = `${header}.${claim}`;
  const sign = crypto.createSign("RSA-SHA256");
  sign.update(unsigned);
  sign.end();
  const signature = base64url(sign.sign(privateKey));
  const jwt = `${unsigned}.${signature}`;

  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!tokenRes.ok) {
    throw new Error(`OAuth token failed: ${await tokenRes.text()}`);
  }
  const json = (await tokenRes.json()) as {
    access_token: string;
    expires_in: number;
  };
  store.accessToken = {
    value: json.access_token,
    expiresAt: Date.now() + (json.expires_in ?? 3600) * 1000,
  };
  return json.access_token;
}

function base64url(input: string | Buffer): string {
  const buf = typeof input === "string" ? Buffer.from(input) : input;
  return buf
    .toString("base64")
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
}
