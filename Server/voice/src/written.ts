import type Anthropic from "@anthropic-ai/sdk";

/**
 * Sent after the text once Claude has finished it. A reply without it was cut short, by Claude
 * reaching `max_tokens` or declining, or by a failure on the way, and the app keeps what was said
 * as it was: the text alone, stopping where it stops, would take the place of all of it.
 */
export const finished = "\u0004";

/** The text of Claude's reply as it comes, and `finished` once all of it has. */
export function written(events: AsyncIterable<Anthropic.Beta.Messages.BetaRawMessageStreamEvent>): ReadableStream<Uint8Array> {
  const encoder = new TextEncoder();
  return new ReadableStream<Uint8Array>({
    async start(controller) {
      let stop: string | null = null;
      try {
        for await (const event of events) {
          if (event.type === "content_block_delta" && event.delta.type === "text_delta") {
            controller.enqueue(encoder.encode(event.delta.text));
          } else if (event.type === "message_delta") {
            stop = event.delta.stop_reason;
          }
        }
      } catch {
        controller.error(new Error("Cut short"));
        return;
      }
      if (stop === "end_turn") controller.enqueue(encoder.encode(finished));
      controller.close();
    },
  });
}
