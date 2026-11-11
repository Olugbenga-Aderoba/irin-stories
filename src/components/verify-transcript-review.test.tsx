import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";
vi.mock("next/navigation", () => ({ useRouter: () => ({ refresh: vi.fn() }) }));

import { VerifyTranscriptReview } from "@/components/verify-transcript-review";

const base = { storyId: "11111111-1111-4111-8111-111111111111", sourceMediaArtifactId: "22222222-2222-4222-8222-222222222222" };

describe("Verify B transcript review UI", () => {
  it("requires eligibility and storyteller consent before offering transcription", () => {
    const blocked = renderToStaticMarkup(<VerifyTranscriptReview {...base} transcriptionEligible={false} transcript={null} />);
    expect(blocked).toContain("explicitly confirmed Yoruba");
    expect(blocked).not.toContain("Create Yoruba transcript");
    const eligible = renderToStaticMarkup(<VerifyTranscriptReview {...base} transcriptionEligible transcript={null} />);
    expect(eligible).toContain("send the current source audio to OpenAI");
    expect(eligible).toContain("Create Yoruba transcript");
  });

  it("shows editable segments, preserves an AI-original view, and offers exact-source approval", () => {
    const markup = renderToStaticMarkup(<VerifyTranscriptReview {...base} transcriptionEligible transcript={{
      artifact_version_id: "33333333-3333-4333-8333-333333333333",
      source_media_artifact_id: base.sourceMediaArtifactId,
      language_code: "yor",
      approved: false,
      segments: [{ id: "seg-1", segment_number: 1, source_start_ms: 0, source_end_ms: 1200, initial_proposal: "Original Yoruba", text_yoruba: "Original Yoruba" }],
    }} />);
    expect(markup).toContain("AI-original transcript");
    expect(markup).toContain("Original Yoruba");
    expect(markup).toContain("Approve Yoruba Source");
    expect(markup).toContain("Save corrections as new version");
  });
});
