import "server-only";
import OpenAI from "openai";
import { z } from "zod";
import type { StoryCutProposalProvider } from "@/lib/craft/story-cut";

const responseSchema = z.object({
  segments: z.array(z.object({
    transcriptSegmentId: z.string().uuid(),
    narrativeRole: z.string().trim().min(1).max(120),
    selectionRationale: z.string().trim().min(1).max(1000),
  }).strict()).min(1).max(100),
}).strict();

export class StoryCutProposalError extends Error {
  constructor() {
    super("The Story Cut proposal could not be generated. Please retry.");
    this.name = "StoryCutProposalError";
  }
}

export const openAIStoryCutProposal: StoryCutProposalProvider = async (segments) => {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) throw new StoryCutProposalError();
  try {
    const client = new OpenAI({ apiKey, timeout: 60_000, maxRetries: 0, logLevel: "off" });
    const response = await client.chat.completions.create({
      model: process.env.OPENAI_STORY_CUT_MODEL ?? "gpt-4o-mini",
      temperature: 0.2,
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: "Select a coherent chronological 90–150 second Story Cut from the provided approved Yoruba transcript segments. Return JSON only with a segments array. Each item must include transcriptSegmentId copied exactly from input, a concise narrativeRole, and a short selectionRationale. Select only existing segments, never invent or rewrite transcript text, preserve their chronological order, and prefer the closest possible duration to 120 seconds. The storyteller will review, remove, reorder, and approve this proposal." },
        { role: "user", content: JSON.stringify(segments.map((segment) => ({ transcriptSegmentId: segment.id, startMs: segment.startMs, endMs: segment.endMs, text: segment.text }))) },
      ],
    });
    const raw = response.choices[0]?.message.content;
    const parsed = responseSchema.safeParse(raw ? JSON.parse(raw) as unknown : null);
    if (!parsed.success) throw new StoryCutProposalError();
    const inputIds = new Set(segments.map((segment) => segment.id));
    const chosenIds = new Set(parsed.data.segments.map((segment) => segment.transcriptSegmentId));
    if (chosenIds.size !== parsed.data.segments.length || parsed.data.segments.some((segment) => !inputIds.has(segment.transcriptSegmentId))) throw new StoryCutProposalError();
    return parsed.data.segments;
  } catch {
    throw new StoryCutProposalError();
  }
};
