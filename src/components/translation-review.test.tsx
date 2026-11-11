import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";
vi.mock("next/navigation", () => ({ useRouter: () => ({ refresh: vi.fn() }) }));

import { TranslationReview } from "@/components/translation-review";

const segment = { id: "translation-1", cut_segment_id: "cut-segment-1", transcript_segment_id: "transcript-segment-1", cue_start_ms: 0, cue_end_ms: 25000,
  source_start_ms: 5000, source_end_ms: 30000, english_text: "A storyteller's words.", initial_proposal: "A storyteller's words.", yoruba_text: "Ọ̀rọ̀ olùsọ̀tàn." };

describe("English translation review UI", () => {
  it("gates translation on approved Story Cut and discloses external AI processing", () => {
    const blocked = renderToStaticMarkup(<TranslationReview storyId="story" cutApproved={false} translation={null} />);
    expect(blocked).toContain("Approve the current Story Cut");
    expect(blocked).not.toContain("Create English translation proposal");
    const ready = renderToStaticMarkup(<TranslationReview storyId="story" cutApproved translation={null} />);
    expect(ready).toContain("English translation is AI-assisted");
    expect(ready).toContain("send the approved Story Cut’s Yoruba transcript segments to OpenAI");
    expect(ready).toContain("Create English translation proposal");
  });

  it("shows Yoruba and English with timestamps, edit and exact-version approval actions", () => {
    const markup = renderToStaticMarkup(<TranslationReview storyId="story" cutApproved translation={{ artifactId: "translation-version", approved: false, segments: [segment] }} />);
    expect(markup).toContain("Yoruba · approved Story Cut");
    expect(markup).toContain("English · AI-assisted proposal");
    expect(markup).toContain("Source video 00:05–00:30");
    expect(markup).toContain("Ọ̀rọ̀ olùsọ̀tàn.");
    expect(markup).toContain("A storyteller&#x27;s words.");
    expect(markup).toContain("Save corrections as new version");
    expect(markup).toContain("Approve English Translation");
    const approved = renderToStaticMarkup(<TranslationReview storyId="story" cutApproved translation={{ artifactId: "translation-version", approved: true, segments: [segment] }} />);
    expect(approved).toContain("exact English translation version and hash");
  });
});
