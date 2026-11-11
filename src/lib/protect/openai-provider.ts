import "server-only";
import OpenAI from "openai";
import { createPrivacyReviewProvider } from "@/lib/protect/privacy";

export const PRIVACY_MODEL = process.env.OPENAI_PRIVACY_MODEL ?? "gpt-4o-mini";

async function complete(segments: readonly { translationSegmentId: string; text: string; startMs: number; endMs: number }[]) {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) throw new Error("Privacy review is unavailable.");
  const client = new OpenAI({ apiKey, timeout: 90_000, maxRetries: 0, logLevel: "off" });
  const response = await client.chat.completions.create({
    model: PRIVACY_MODEL, temperature: 0.1, response_format: { type: "json_object" },
    messages: [
      { role: "system", content: "Identify potential privacy risks in this English story for the storyteller to review. AI only proposes findings and safer alternatives; never decide or resolve them. Do not infer sensitive facts not present. Return JSON {findings:[{translationSegmentId,riskCategory,affectedPassage,suggestedSaferAlternative}]}. Each finding must quote a concise affected passage from one supplied segment and use its ID. Return an empty findings array when no specific risk is supported." },
      { role: "user", content: JSON.stringify(segments) },
    ],
  });
  const content = response.choices[0]?.message.content;
  if (!content) throw new Error("Privacy review is unavailable.");
  return JSON.parse(content) as unknown;
}

export const openAIPrivacyReview = createPrivacyReviewProvider(complete);
