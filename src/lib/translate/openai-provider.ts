import "server-only";
import OpenAI from "openai";
import { z } from "zod";
import { englishTranslationSchema, type YorubaToEnglishProvider } from "@/lib/translate/contract";

const responseSchema = z.object({ segments: z.array(englishTranslationSchema).min(1).max(1000) }).strict();
export const TRANSLATION_MODEL = process.env.OPENAI_TRANSLATION_MODEL ?? "gpt-4o-mini";

export class EnglishTranslationError extends Error {
  constructor() { super("The English translation could not be generated. Please retry."); this.name = "EnglishTranslationError"; }
}

export type TranslationCompletion = (segments: readonly { cutSegmentId: string; startMs: number; endMs: number; text: string }[]) => Promise<unknown>;

async function completeWithOpenAI(segments: readonly { cutSegmentId: string; startMs: number; endMs: number; text: string }[]) {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) throw new EnglishTranslationError();
  const client = new OpenAI({ apiKey, timeout: 90_000, maxRetries: 0, logLevel: "off" });
  const response = await client.chat.completions.create({
    model: TRANSLATION_MODEL,
    temperature: 0.2,
    response_format: { type: "json_object" },
    messages: [
      { role: "system", content: "Translate each Yoruba segment into clear, faithful English. Return JSON only: {segments:[{cutSegmentId,englishText}]}. Include every provided cutSegmentId exactly once and in the same order. Do not summarize, add facts, omit meaning, or change IDs. Preserve culturally specific terms when there is no faithful short equivalent." },
      { role: "user", content: JSON.stringify(segments.map((segment) => ({ cutSegmentId: segment.cutSegmentId, startMs: segment.startMs, endMs: segment.endMs, yorubaText: segment.text }))) },
    ],
  });
  const content = response.choices[0]?.message.content;
  if (!content) throw new EnglishTranslationError();
  return JSON.parse(content) as unknown;
}

export function createYorubaToEnglishProvider(completion: TranslationCompletion = completeWithOpenAI): YorubaToEnglishProvider {
  return async (segments) => {
    try {
      const raw = await completion(segments);
      const parsed = responseSchema.safeParse(raw);
      if (!parsed.success || parsed.data.segments.length !== segments.length) throw new EnglishTranslationError();
      if (parsed.data.segments.some((item, index) => item.cutSegmentId !== segments[index]?.cutSegmentId)) throw new EnglishTranslationError();
      return parsed.data.segments;
    } catch {
      throw new EnglishTranslationError();
    }
  };
}

export const openAIYorubaToEnglish = createYorubaToEnglishProvider();
