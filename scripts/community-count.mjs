import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";
import { fileURLToPath } from "node:url";

export const PRODUCT_ID = "com.grandelevas.wakemeup.yearly";

const PAID_COLUMNS = [
  "Active Standard Price Subscriptions",
  "Active Pay Up Front Introductory Offer Subscriptions",
  "Active Pay as You Go Introductory Offer Subscriptions",
  "Pay Up Front Promotional Offer Subscriptions",
  "Pay As You Go Promotional Offer Subscriptions",
  "Pay Up Front Offer Code Subscriptions",
  "Pay As You Go Offer Code Subscriptions",
];

export function parseTsv(text) {
  const lines = text.replace(/^\uFEFF/, "").split(/\r?\n/).filter((line) => line.trim().length > 0);
  if (lines.length === 0) return [];
  const headers = lines[0].split("\t").map((header) => header.trim());
  return lines.slice(1).map((line) => {
    const cells = line.split("\t");
    const row = {};
    headers.forEach((header, index) => {
      row[header] = (cells[index] ?? "").trim();
    });
    return row;
  });
}

function cell(row, name) {
  const wanted = name.toLowerCase();
  for (const [key, value] of Object.entries(row)) {
    if (key.toLowerCase() === wanted) return value;
  }
  return "";
}

function integer(value) {
  const parsed = Number(String(value).replace(/,/g, ""));
  return Number.isFinite(parsed) ? parsed : 0;
}

export function matchesYearlyProduct(row) {
  if (Object.values(row).some((value) => value === PRODUCT_ID)) return true;
  const duration = cell(row, "Standard Subscription Duration");
  const name = cell(row, "Subscription Name").toLowerCase();
  return duration === "1 Year" && (name.includes("wakito") || name.includes("yearly") || name.includes("year"));
}

export function countActiveSubscribers(rows) {
  const matched = rows.filter(matchesYearlyProduct);
  if (matched.length === 0) return null;
  const total = matched.reduce((sum, row) => {
    return sum + PAID_COLUMNS.reduce((columnSum, column) => columnSum + integer(cell(row, column)), 0);
  }, 0);
  return Math.max(0, total);
}

export function countSalesUnits(rows) {
  const matched = rows.filter((row) => cell(row, "SKU") === PRODUCT_ID || Object.values(row).includes(PRODUCT_ID));
  if (matched.length === 0) return null;
  const total = matched.reduce((sum, row) => sum + integer(cell(row, "Units")), 0);
  return Math.max(0, total);
}

function warning(message) {
  console.log(`::warning::${message}`);
}

function privateKey() {
  const raw = process.env.ASC_PRIVATE_KEY ?? "";
  const pem = raw.includes("\\n") ? raw.replace(/\\n/g, "\n") : raw;
  return crypto.createPrivateKey(pem);
}

function token() {
  const header = Buffer.from(JSON.stringify({ alg: "ES256", kid: process.env.ASC_KEY_ID, typ: "JWT" })).toString("base64url");
  const now = Math.floor(Date.now() / 1000);
  const payload = Buffer.from(JSON.stringify({
    iss: process.env.ASC_ISSUER_ID,
    iat: now,
    exp: now + 600,
    aud: "appstoreconnect-v1",
  })).toString("base64url");
  const signature = crypto.sign("sha256", Buffer.from(`${header}.${payload}`), {
    key: privateKey(),
    dsaEncoding: "ieee-p1363",
  }).toString("base64url");
  return `${header}.${payload}.${signature}`;
}

function decodeBody(buffer) {
  if (buffer.length >= 2 && buffer[0] === 0x1f && buffer[1] === 0x8b) {
    return zlib.gunzipSync(buffer).toString("utf8");
  }
  return buffer.toString("utf8");
}

async function downloadReport({ reportType, frequency, version, reportDate, vendor }) {
  const url = new URL("https://api.appstoreconnect.apple.com/v1/salesReports");
  url.searchParams.set("filter[reportType]", reportType);
  url.searchParams.set("filter[reportSubType]", "SUMMARY");
  url.searchParams.set("filter[frequency]", frequency);
  url.searchParams.set("filter[reportDate]", reportDate);
  url.searchParams.set("filter[vendorNumber]", vendor);
  url.searchParams.set("filter[version]", version);
  const response = await fetch(url, {
    headers: {
      Authorization: `Bearer ${token()}`,
      Accept: "application/a-gzip",
    },
  });
  const buffer = Buffer.from(await response.arrayBuffer());
  if (response.status === 404) return null;
  if (!response.ok) {
    const detail = decodeBody(buffer).replace(/\s+/g, " ").slice(0, 300);
    warning(`${reportType} report ${reportDate} returned HTTP ${response.status}. ${detail}`);
    return null;
  }
  const text = decodeBody(buffer);
  if (text.trim().startsWith("{")) {
    warning(`${reportType} report ${reportDate} was not a table.`);
    return null;
  }
  return text;
}

function recentDays(count) {
  const dates = [];
  const today = new Date();
  for (let offset = 1; offset <= count; offset += 1) {
    const day = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate() - offset));
    dates.push(day.toISOString().slice(0, 10));
  }
  return dates;
}

function writeCount(count, reportDate) {
  const destination = path.join("stats", "community.json");
  const next = `${JSON.stringify({ userCount: count, userCountDate: reportDate }, null, 2)}\n`;
  fs.mkdirSync("stats", { recursive: true });
  if (fs.existsSync(destination) && fs.readFileSync(destination, "utf8") === next) {
    console.log(`Community count is already ${count}.`);
    return;
  }
  fs.writeFileSync(destination, next);
  console.log(`Wrote userCount ${count} from ${reportDate}.`);
}

async function main() {
  const vendor = (process.env.ASC_VENDOR_NUMBER ?? "").trim();
  if (!vendor) {
    warning("ASC_VENDOR_NUMBER is not set. In App Store Connect open Payments and Financial Reports and copy the Vendor Number, then add it as a repository secret or variable named ASC_VENDOR_NUMBER. Skipping the community count.");
    return;
  }
  if (!process.env.ASC_KEY_ID || !process.env.ASC_ISSUER_ID || !process.env.ASC_PRIVATE_KEY) {
    warning("The App Store Connect API key secrets are missing. Skipping the community count.");
    return;
  }

  for (const reportDate of recentDays(6)) {
    const text = await downloadReport({
      reportType: "SUBSCRIPTION",
      frequency: "DAILY",
      version: "1_3",
      reportDate,
      vendor,
    });
    if (!text) continue;
    const count = countActiveSubscribers(parseTsv(text));
    if (count == null) continue;
    writeCount(count, reportDate);
    return;
  }

  const year = String(new Date().getUTCFullYear());
  for (const version of ["1_0", "1_1"]) {
    const text = await downloadReport({
      reportType: "SALES",
      frequency: "YEARLY",
      version,
      reportDate: year,
      vendor,
    });
    if (!text) continue;
    const count = countSalesUnits(parseTsv(text));
    if (count == null) continue;
    writeCount(count, year);
    return;
  }

  console.log("No subscription or sales report for com.grandelevas.wakemeup.yearly yet. Leaving the community count unchanged.");
}

const entry = process.argv[1] ? path.resolve(process.argv[1]) : "";
if (entry && fileURLToPath(import.meta.url) === entry) {
  main().catch((error) => {
    warning(error instanceof Error ? error.message : "Community count failed.");
    process.exitCode = 0;
  });
}
