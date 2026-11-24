// Small App Store Connect API helper for testflight.yml. Node only, no packages.
//
//   node ios/scripts/asc.mjs check-key
//       Fails fast, before the long build, if the API key is not accepted.
//   node ios/scripts/asc.mjs wait-build <bundle id> <version> <build>
//       Waits until App Store Connect has processed an uploaded build.
//
// Needs ASC_KEY_PATH (the .p8 file), ASC_KEY_ID and ASC_ISSUER_ID in the environment.
// Prints no key material and no account details.
import { readFileSync } from "node:fs";
import { createPrivateKey, sign } from "node:crypto";

const { ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID } = process.env;
const [command, ...args] = process.argv.slice(2);

if (!ASC_KEY_PATH || !ASC_KEY_ID || !ASC_ISSUER_ID) {
  console.error("ASC_KEY_PATH, ASC_KEY_ID and ASC_ISSUER_ID must be set.");
  process.exit(2);
}

function token() {
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString("base64url");
  const now = Math.floor(Date.now() / 1000);
  const unsigned = `${encode({ alg: "ES256", kid: ASC_KEY_ID, typ: "JWT" })}.${encode({
    iss: ASC_ISSUER_ID,
    iat: now,
    exp: now + 15 * 60,
    aud: "appstoreconnect-v1",
  })}`;
  const key = createPrivateKey(readFileSync(ASC_KEY_PATH));
  const signature = sign("sha256", Buffer.from(unsigned), { key, dsaEncoding: "ieee-p1363" });
  return `${unsigned}.${signature.toString("base64url")}`;
}

async function api(path) {
  const response = await fetch(`https://api.appstoreconnect.apple.com${path}`, {
    headers: { authorization: `Bearer ${token()}` },
  });
  if (!response.ok) {
    const body = (await response.text()).slice(0, 400);
    throw new Error(`GET ${path.split("?")[0]} answered HTTP ${response.status}: ${body}`);
  }
  return response.json();
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function findApp(bundleId) {
  const found = await api(`/v1/apps?filter[bundleId]=${encodeURIComponent(bundleId)}&fields[apps]=bundleId,name`);
  const app = found.data.find((item) => item.attributes.bundleId === bundleId);
  if (!app) {
    throw new Error(`App Store Connect has no app record for ${bundleId}. Create it first (README, App Store Connect).`);
  }
  return app.id;
}

if (command === "check-key") {
  try {
    await api("/v1/apps?limit=1&fields[apps]=bundleId");
    console.log("The App Store Connect API key is accepted.");
  } catch (error) {
    console.error(`::error::The App Store Connect API key was not accepted: ${error.message}`);
    console.error("Check ASC_KEY_ID, ASC_ISSUER_ID and ASC_PRIVATE_KEY (the whole .p8 file, including the BEGIN and END lines).");
    process.exit(1);
  }
} else if (command === "wait-build") {
  const [bundleId, version, build] = args;
  if (!bundleId || !version || !build) {
    console.error("usage: node asc.mjs wait-build <bundle id> <version> <build>");
    process.exit(2);
  }
  const appId = await findApp(bundleId);
  const query = `/v1/builds?filter[app]=${appId}&filter[version]=${encodeURIComponent(build)}` +
    `&filter[preReleaseVersion.version]=${encodeURIComponent(version)}&fields[builds]=version,processingState`;
  const deadline = Date.now() + 30 * 60 * 1000;
  let last = "";
  for (;;) {
    let state = "not listed yet";
    try {
      const found = await api(query);
      state = found.data[0]?.attributes?.processingState ?? state;
    } catch (error) {
      state = `unknown (${error.message})`;
    }
    if (state !== last) {
      console.log(`${version} (${build}): ${state}`);
      last = state;
    }
    if (state === "VALID") {
      console.log("Processed. The build is in App Store Connect → TestFlight.");
      break;
    }
    if (state === "INVALID" || state === "FAILED") {
      console.error(`::error::App Store Connect marked build ${build} as ${state}. Apple emails the reason to the account holder; App Store Connect → TestFlight shows it too.`);
      process.exit(1);
    }
    if (Date.now() > deadline) {
      console.log(`::warning::Still ${state} after 30 minutes. The upload went through; Apple finishes processing on its own.`);
      break;
    }
    await sleep(30 * 1000);
  }
} else {
  console.error("usage: node asc.mjs check-key | wait-build <bundle id> <version> <build>");
  process.exit(2);
}
