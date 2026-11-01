import { test } from "node:test";
import assert from "node:assert/strict";
import { finished, written } from "../src/written.ts";

async function* events(...list) {
  yield* list;
}
const text = (text) => ({ type: "content_block_delta", index: 0, delta: { type: "text_delta", text } });
const stop = (stop_reason) => ({ type: "message_delta", delta: { stop_reason, stop_sequence: null }, usage: {} });
const read = (stream) => new Response(stream).text();

test("a reply Claude finished ends with the mark", async () => {
  const reply = written(events(text("- [ ] eggs\n"), text("- [ ] bread"), stop("end_turn")));
  assert.equal(await read(reply), `- [ ] eggs\n- [ ] bread${finished}`);
});

test("one cut short at max_tokens, or declined, has none", async () => {
  assert.equal(await read(written(events(text("Tidied, then"), stop("max_tokens")))), "Tidied, then");
  assert.equal(await read(written(events(text("Tid"), stop("refusal")))), "Tid");
});

test("one broken off fails", async () => {
  async function* broken() {
    yield text("Tid");
    throw new Error("Connection lost");
  }
  await assert.rejects(read(written(broken())));
});
