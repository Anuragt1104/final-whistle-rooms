/**
 * Provider-agnostic LLM chat client (server-side only).
 *
 * Prefers a generic OpenAI-compatible endpoint (Groq free tier, xAI, …) via
 * LLM_API_URL + LLM_API_KEY + LLM_MODEL, and falls back to the Anthropic key
 * already used for recaps. Callers must treat every throw as "use the local
 * template" — this client never retries and never blocks a game tick.
 */

export function llmConfigured(): boolean {
  return !!((process.env.LLM_API_URL && process.env.LLM_API_KEY) || process.env.ANTHROPIC_API_KEY);
}

export interface ChatJSONOptions {
  system: string;
  user: string;
  maxTokens?: number;
  timeoutMs?: number;
}

/** Ask the configured LLM for a JSON object; parsed result or throw. */
export async function chatJSON(opts: ChatJSONOptions): Promise<unknown> {
  const timeoutMs = opts.timeoutMs ?? 3000;
  const maxTokens = opts.maxTokens ?? 400;
  const text =
    process.env.LLM_API_URL && process.env.LLM_API_KEY
      ? await openAICompatible(opts.system, opts.user, maxTokens, timeoutMs)
      : await anthropic(opts.system, opts.user, maxTokens, timeoutMs);
  return JSON.parse(stripFences(text));
}

function stripFences(text: string): string {
  const t = text.trim();
  const m = t.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/);
  return m ? m[1] : t;
}

async function openAICompatible(system: string, user: string, maxTokens: number, timeoutMs: number): Promise<string> {
  const base = (process.env.LLM_API_URL as string).replace(/\/$/, "");
  const res = await fetch(`${base}/chat/completions`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${process.env.LLM_API_KEY}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: process.env.LLM_MODEL ?? "llama-3.3-70b-versatile",
      temperature: 0.8,
      max_tokens: maxTokens,
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: system },
        { role: "user", content: user },
      ],
    }),
    signal: AbortSignal.timeout(timeoutMs),
  });
  if (!res.ok) throw new Error(`LLM chat failed: ${res.status}`);
  const data = (await res.json()) as { choices?: Array<{ message?: { content?: string } }> };
  const text = data.choices?.[0]?.message?.content;
  if (!text) throw new Error("LLM chat empty");
  return text;
}

async function anthropic(system: string, user: string, maxTokens: number, timeoutMs: number): Promise<string> {
  if (!process.env.ANTHROPIC_API_KEY) throw new Error("No LLM configured");
  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": process.env.ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: process.env.LLM_MODEL ?? "claude-haiku-4-5-20251001",
      max_tokens: maxTokens,
      system,
      messages: [{ role: "user", content: user }],
    }),
    signal: AbortSignal.timeout(timeoutMs),
  });
  if (!res.ok) throw new Error(`LLM chat failed: ${res.status}`);
  const data = (await res.json()) as { content?: Array<{ type: string; text?: string }> };
  const text = data.content?.find((c) => c.type === "text")?.text;
  if (!text) throw new Error("LLM chat empty");
  return text;
}
