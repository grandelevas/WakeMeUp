import assert from "node:assert/strict";
import test from "node:test";
import { countActiveSubscribers, countSalesUnits, parseTsv } from "./community-count.mjs";

const subscription = [
  "Subscription Name\tStandard Subscription Duration\tActive Standard Price Subscriptions\tActive Free Trial Introductory Offer Subscriptions\tActive Pay Up Front Introductory Offer Subscriptions",
  "Wakito Yearly\t1 Year\t4\t9\t1",
  "Other Monthly\t1 Month\t20\t0\t0",
].join("\n");

test("active subscribers ignore free trials and other products", () => {
  const count = countActiveSubscribers(parseTsv(subscription));
  assert.equal(count, 5);
});

test("a report with no yearly Wakito rows is not a zero", () => {
  const text = "Subscription Name\tStandard Subscription Duration\tActive Standard Price Subscriptions\nOther\t1 Month\t3\n";
  assert.equal(countActiveSubscribers(parseTsv(text)), null);
});

test("sales units fall back to the yearly product id", () => {
  const text = "SKU\tUnits\ncom.grandelevas.wakemeup.yearly\t2\nother\t8\ncom.grandelevas.wakemeup.yearly\t-1\n";
  assert.equal(countSalesUnits(parseTsv(text)), 1);
});
