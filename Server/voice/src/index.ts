import Anthropic from "@anthropic-ai/sdk";

interface Env {
  /** Claude, for tidying what was said. */
  ANTHROPIC_API_KEY: string;
  /** Soniox, for the short-lived keys the app transcribes with. */
  SONIOX_API_KEY: string;
  /** What Bite sends to be let in. A stopgap till App Attest. */
  APP_TOKEN: string;
}

const model = "claude-sonnet-5-5";

/**
 * How what was said into a page is tidied: one person speaking is tidied into what they meant to
 * write, in the page's own kind of lines; several, a conversation, are only cleaned up, everything
 * said kept as said, not made into meeting notes (user, 2026-11-01).
 */
const prompts = {
  one: `You turn what someone said into a note into the text they meant to write there.

You're given the note as it was before they spoke, in <page>, and what they said, in <said>: a speech-to-text transcript, written into the note as they spoke, which they may have corrected or added to by typing.

- Write what they meant: drop fillers (嗯, 那个, 就是, um, like), false starts and repetition, and apply their corrections ("三点，不对，四点" becomes 四点), dropping whatever they took back.
- Keep their words and languages as said: Chinese with English words in it stays that way. Don't translate, summarize or add anything, unless they ask.
- Fix words the transcript misheard, often for others that sound the same (同音字, as 交水费 heard as 胶水费), from what makes sense said aloud and from names and terms in the note. Leave a word as it is if you can't tell what was meant.
- Fit the note: write in its kind of lines and its style. Things to do, added to a to-do list, are to-dos; items added to a list are items of it. Otherwise write sentences in paragraphs, punctuated as the language is written: full-width marks (，。？！：) in Chinese.
- If they say how to lay it out ("列成清单", "写成待办", "make this a list", "翻译成英文"), do it, and leave the instruction out.
- Write Markdown as the note does: "# " headings, "- " bullets, "1. " numbered items, "- [ ] " to-dos, "> " quotes, **bold**. Every line is a paragraph or item of its own: leave no blank lines between them, unless the note does.
- Output only the text that goes in place of <said>: nothing from the note before it, and no comment.`,
  several: `You clean up a conversation written into a note as it was said: several people speaking, written down by speech-to-text as they spoke, maybe corrected or added to by typing.

You're given the note as it was before, in <page>, and the conversation, in <said>.

- Fix words the transcript misheard, often for others that sound the same (同音字, as 交水费 heard as 胶水费), from what makes sense said aloud and from names and terms in the note, and typos. Leave a word as it is if you can't tell what was meant.
- Add punctuation as the language is written, full-width marks (，。？！：) in Chinese, and break it into paragraphs where the speaker changes or the subject does: a line each, with no blank lines between them, unless the note has them.
- Keep everything that was said, in the words and languages it was said in. Don't summarize, translate, reorder or add anything, and don't make it into notes.
- Output only the cleaned-up text that goes in place of <said>: nothing from the note before it, and no comment.`,
} as const;

export default {
  async fetch(request, env): Promise<Response> {
    if (request.method !== "POST") return new Response("Not found", { status: 404 });
    if (!(await isBite(request, env))) return new Response("Unauthorized", { status: 401 });
    switch (new URL(request.url).pathname) {
      case "/v1/soniox-key":
        return sonioxKey(env);
      case "/v1/tidy":
        return tidy(request, env);
      default:
        return new Response("Not found", { status: 404 });
    }
  },
} satisfies ExportedHandler<Env>;

/** Whether the request carries Bite's token, compared in constant time. */
async function isBite(request: Request, env: Env): Promise<boolean> {
  const header = request.headers.get("Authorization") ?? "";
  if (!header.startsWith("Bearer ") || !env.APP_TOKEN) return false;
  const given = new TextEncoder().encode(header.slice("Bearer ".length));
  const expected = new TextEncoder().encode(env.APP_TOKEN);
  return given.byteLength === expected.byteLength && crypto.subtle.timingSafeEqual(given, expected);
}

/**
 * A Soniox key for one live transcription: it must be used within 5 minutes, and once only, and
 * the transcription it opens runs for 5 hours at most, as long as Soniox allows.
 */
async function sonioxKey(env: Env): Promise<Response> {
  const response = await fetch("https://api.soniox.com/v1/auth/temporary-api-key", {
    method: "POST",
    headers: { Authorization: `Bearer ${env.SONIOX_API_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      usage_type: "transcribe_websocket",
      expires_in_seconds: 300,
      single_use: true,
      max_session_duration_seconds: 18000,
    }),
  });
  if (!response.ok) return new Response(`Soniox answered ${response.status}`, { status: 502 });
  const { api_key, expires_at } = await response.json<{ api_key: string; expires_at: string }>();
  return Response.json({ api_key, expires_at });
}

/**
 * What was said into a page, tidied by Claude, streamed back as plain text as it's written. The
 * request has what was said as it stands on the page, `said`, the page before it, `page`, both
 * Markdown, and how many people spoke, `speakers`. Sonnet at low effort, thinking only between
 * tools, which tidying calls none of: done 0.3 s behind the fastest in a test of ten dictations,
 * for a quarter of what Opus in fast mode costs (user, 2026-11-01).
 */
async function tidy(request: Request, env: Env): Promise<Response> {
  const body = await request.json<{ said?: string; page?: string; speakers?: number }>().catch(() => null);
  const said = body?.said?.trim();
  if (!said) return new Response("Nothing to tidy", { status: 400 });
  const page = body?.page?.trim() ?? "";
  const system = (body?.speakers ?? 1) > 1 ? prompts.several : prompts.one;
  const client = new Anthropic({ apiKey: env.ANTHROPIC_API_KEY });
  let events;
  try {
    events = await client.beta.messages.create({
      model,
      max_tokens: 16000,
      system,
      messages: [{ role: "user", content: `<page>\n${page}\n</page>\n<said>\n${said}\n</said>` }],
      thinking: { type: "between_tools" },
      output_config: { effort: "low" },
      fallbacks: "default",
      betas: ["server-side-fallback-2026-07-01"],
      stream: true,
    });
  } catch (error) {
    return failure(error);
  }
  const encoder = new TextEncoder();
  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      try {
        for await (const event of events) {
          if (event.type === "content_block_delta" && event.delta.type === "text_delta") {
            controller.enqueue(encoder.encode(event.delta.text));
          }
        }
      } catch {
        // Cut short: the app keeps what was said as it was.
        controller.error(new Error("Cut short"));
        return;
      }
      controller.close();
    },
  });
  return new Response(stream, { headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" } });
}

function failure(error: unknown): Response {
  if (error instanceof Anthropic.RateLimitError) return new Response("Busy", { status: 429 });
  if (error instanceof Anthropic.APIError) return new Response(`Claude answered ${error.status}`, { status: 502 });
  return new Response("Couldn't reach Claude", { status: 502 });
}
