#!/usr/bin/env node
import fs from "node:fs";

const sessionGuid = process.argv[2];
if (!sessionGuid) {
  console.error("Usage: webservice_probe.mjs <sessionGuid>");
  process.exit(2);
}

const authSource = fs.readFileSync("lib/services/auth0_m2m_service.dart", "utf8");
const extract = (name) => {
  const match = authSource.match(new RegExp(`final String _${name} =\\s*"([^"]+)"`));
  if (!match) {
    throw new Error(`Missing ${name} in auth0_m2m_service.dart`);
  }
  return match[1];
};

const clientId = extract("clientId");
const clientSecret = extract("clientSecret");
const audience = extract("audience");
const tokenUrl = extract("tokenUrl");
const baseUrl = "https://hydracam.azurewebsites.net/api";

async function responseSummary(response) {
  const body = await response.text();
  return {
    status: response.status,
    statusText: response.statusText,
    body,
  };
}

const tokenResponse = await fetch(tokenUrl, {
  method: "POST",
  headers: {"Content-Type": "application/json"},
  body: JSON.stringify({
    client_id: clientId,
    client_secret: clientSecret,
    audience,
    grant_type: "client_credentials",
  }),
});

const tokenBody = await tokenResponse.json();
if (!tokenResponse.ok || !tokenBody.access_token) {
  console.log(JSON.stringify({
    checkedAt: new Date().toISOString(),
    sessionGuid,
    tokenStatus: tokenResponse.status,
    tokenError: tokenBody.error ?? "missing_access_token",
  }, null, 2));
  process.exit(1);
}

const token = tokenBody.access_token;
const probes = [];

async function probe(name, url, options = {}) {
  const response = await fetch(url, {
    ...options,
    headers: {
      ...(options.headers ?? {}),
      Authorization: `Bearer ${token}`,
    },
  });
  probes.push({
    name,
    url,
    ...(await responseSummary(response)),
  });
}

const appUploadUrl = new URL(`${baseUrl}/sessions/upload-media`);
appUploadUrl.searchParams.set("sessionGuid", sessionGuid);
appUploadUrl.searchParams.set("isPhoto", "true");

const legacyUploadUrl = new URL(`${baseUrl}/hydracam/UploadMedia`);
legacyUploadUrl.searchParams.set("sessionGuid", sessionGuid);
legacyUploadUrl.searchParams.set("isPhoto", "true");

const sessionsByCourtUrl = new URL(`${baseUrl}/sessions`);
sessionsByCourtUrl.searchParams.set("courtGuid", sessionGuid);

await probe("app_upload_empty_multipart", appUploadUrl, {
  method: "POST",
  body: new FormData(),
});

await probe("legacy_upload_empty_multipart", legacyUploadUrl, {
  method: "POST",
  body: new FormData(),
});

await probe("sessions_by_court_guid_same_value", sessionsByCourtUrl, {
  method: "GET",
});

console.log(JSON.stringify({
  checkedAt: new Date().toISOString(),
  sessionGuid,
  tokenStatus: tokenResponse.status,
  probes,
}, null, 2));
