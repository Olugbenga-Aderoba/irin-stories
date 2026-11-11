import "server-only";

import { createReadStream } from "node:fs";
import OpenAI from "openai";
import { normalizeYorubaTranscriptResponse, YorubaTranscriptionError, type YorubaTranscriptSegment } from "@/lib/verify/transcript-contract";

export const TRANSCRIPTION_MODEL = "gpt-transcribe" as const;
export { YorubaTranscriptionError };

export async function transcribeYoruba(audioPath: string, apiKey = process.env.OPENAI_API_KEY): Promise<YorubaTranscriptSegment[]> {
  if (!apiKey) throw new YorubaTranscriptionError();
  try {
    const client = new OpenAI({ apiKey, timeout: 15 * 60_000, maxRetries: 0, logLevel: "off" });
    const response = await client.audio.transcriptions.create({
      file: createReadStream(audioPath),
      model: TRANSCRIPTION_MODEL,
      language: "yo",
      response_format: "verbose_json",
      timestamp_granularities: ["segment"],
    });
    return normalizeYorubaTranscriptResponse(response);
  } catch {
    throw new YorubaTranscriptionError();
  }
}
