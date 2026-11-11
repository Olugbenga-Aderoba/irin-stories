import { renderToStaticMarkup } from "react-dom/server";
import { beforeEach, describe, expect, it, vi } from "vitest";

const refresh = vi.fn();
vi.mock("next/navigation", () => ({ useRouter: () => ({ refresh }) }));

import { VerifyLanguagePanel } from "@/components/verify-language-panel";

const base = {
  storyId: "11111111-1111-4111-8111-111111111111",
  sourceMediaArtifactId: "22222222-2222-4222-8222-222222222222",
  filename: "private.webm",
  playbackUrl: "",
  verification: { id: "x", status: "READY", actual_container: "webm", actual_format_names: "webm", actual_duration_ms: 60000, has_video: true, has_audio: true, audio_codec: "opus", video_codec: "vp8", video_width: 64, video_height: 64, client_metadata_mismatches: [] },
  latestReview: null,
  transcriptionEligible: false,
  noReliableDetection: true,
};

describe("storyteller-selected language fallback UI", () => {
  beforeEach(() => refresh.mockReset());

  it("offers direct Yoruba selection after unreliable detection without claiming AI detected it", () => {
    const markup = renderToStaticMarkup(<VerifyLanguagePanel {...base} humanDecision={null} />);
    expect(markup).toContain("We couldn&#x27;t identify the original language reliably");
    expect(markup).toContain("Select Yoruba");
    expect(markup).toContain("Try detection again");
    expect(markup).not.toContain("Detected: Yoruba");
  });

  it("shows selection as pending and not eligible until confirmation", () => {
    const markup = renderToStaticMarkup(<VerifyLanguagePanel {...base} humanDecision={{ id: "decision-1", state: "selected", selected_language_code: "yor", selected_language_name: "Yoruba", decision_origin: "storyteller_selected" }} />);
    expect(markup).toContain("Selected, awaiting confirmation");
    expect(markup).toContain("Transcription: Not yet eligible");
    expect(markup).toContain("Confirm Yoruba");
    expect(markup).not.toContain("Detected: Yoruba");
  });

  it("shows storyteller confirmation and eligibility only in the confirmed state", () => {
    const markup = renderToStaticMarkup(<VerifyLanguagePanel {...base} noReliableDetection={false} transcriptionEligible humanDecision={{ id: "decision-1", state: "confirmed", selected_language_code: "yor", selected_language_name: "Yoruba", decision_origin: "storyteller_selected" }} />);
    expect(markup).toContain("Confirmed by storyteller");
    expect(markup).toContain("Eligible for the next Verify step");
    expect(markup).not.toContain("Detected: Yoruba");
  });
});
