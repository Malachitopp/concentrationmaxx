// Small App Store Connect API helper for testflight.yml. Node only, no packages.
//
//   node ios/scripts/asc.mjs check-key
//       Fails fast, before the long build, if the API key is not accepted.
//   node ios/scripts/asc.mjs wait-build <bundle id> <version> <build>
//       Waits until App Store Connect has processed an uploaded build.
//   node ios/scripts/asc.mjs distribute-internal <bundle id> <version> <build>
//       Makes sure a processed build is in the app's internal testing groups, so it
//       shows up in the testers' TestFlight app. Never touches external groups: those
//       go through Apple's beta review and are submitted by hand.
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

// GET by default. With `body`, sends it as JSON with `method` (POST unless given).
async function api(path, { method, body } = {}) {
  const verb = method ?? (body ? "POST" : "GET");
  const headers = { authorization: `Bearer ${token()}` };
  if (body) headers["content-type"] = "application/json";
  const response = await fetch(`https://api.appstoreconnect.apple.com${path}`, {
    method: verb,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!response.ok) {
    const text = (await response.text()).slice(0, 400);
    throw new Error(`${verb} ${path.split("?")[0]} answered HTTP ${response.status}: ${text}`);
  }
  // Relationship changes answer 204 with no body.
  return response.status === 204 ? null : response.json();
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
} else if (command === "distribute-internal") {
  const [bundleId, version, build] = args;
  if (!bundleId || !version || !build) {
    console.error("usage: node asc.mjs distribute-internal <bundle id> <version> <build>");
    process.exit(2);
  }
  try {
    const appId = await findApp(bundleId);
    const builds = await api(`/v1/builds?filter[app]=${appId}&filter[version]=${encodeURIComponent(build)}` +
      `&filter[preReleaseVersion.version]=${encodeURIComponent(version)}&fields[builds]=version,processingState`);
    const uploaded = builds.data[0];
    if (!uploaded) {
      console.error(`::error::App Store Connect does not list ${version} (${build}), so it cannot be given to testers.`);
      process.exit(1);
    }
    if (uploaded.attributes?.processingState !== "VALID") {
      console.log(`::warning::${version} (${build}) is still ${uploaded.attributes?.processingState}. Add it to your testing group in App Store Connect → TestFlight once Apple has processed it.`);
      process.exit(0);
    }

    // No field list here: the attributes are read defensively instead, so a renamed
    // attribute cannot turn the request into an error.
    const groups = (await api(`/v1/betaGroups?filter[app]=${appId}&limit=200`)).data
      .filter((group) => group.attributes?.isInternalGroup === true);
    if (groups.length === 0) {
      console.log("::warning::This app has no internal testing group yet, so nobody receives the build. Create one in App Store Connect → TestFlight → Internal Testing (README section 3.2).");
      process.exit(0);
    }

    // Groups are numbered, not named: this log is public and group names are the owner's.
    let delivered = 0;
    for (const [index, group] of groups.entries()) {
      const label = `Internal testing group ${index + 1} of ${groups.length}`;
      try {
        if (group.attributes?.hasAccessToAllBuilds === true) {
          console.log(`${label}: receives every build automatically.`);
          delivered += 1;
          continue;
        }
        const listed = await api(`/v1/betaGroups/${group.id}/builds?limit=200&fields[builds]=version`);
        if (listed.data.some((item) => item.id === uploaded.id)) {
          console.log(`${label}: already has ${version} (${build}).`);
          delivered += 1;
          continue;
        }
        await api(`/v1/betaGroups/${group.id}/relationships/builds`, {
          body: { data: [{ type: "builds", id: uploaded.id }] },
        });
        console.log(`${label}: ${version} (${build}) added.`);
        delivered += 1;
      } catch (error) {
        console.log(`::warning::${label}: the build could not be added (${error.message}). Add it in App Store Connect → TestFlight.`);
      }
    }
    if (delivered === 0) {
      console.error(`::error::${version} (${build}) is uploaded and processed, but it is in no internal testing group. Add it in App Store Connect → TestFlight.`);
      process.exit(1);
    }
    console.log(`${version} (${build}) is available to ${delivered} of ${groups.length} internal testing group(s). It appears in the testers' TestFlight app within a few minutes.`);
  } catch (error) {
    // The upload itself is done by now; only handing the build to testers failed.
    console.error(`::error::The build could not be given to the internal testers: ${error.message}. Add it in App Store Connect → TestFlight.`);
    process.exit(1);
  }
} else {
  console.error("usage: node asc.mjs check-key | wait-build <bundle id> <version> <build> | distribute-internal <bundle id> <version> <build>");
  process.exit(2);
}
