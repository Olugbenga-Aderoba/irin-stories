import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { ProtectReview } from "@/components/protect-review";

describe("Protect review UI", () => {
  it("shows an AI proposal as unresolved and gives the storyteller all four decisions", () => {
    const html = renderToStaticMarkup(<ProtectReview storyId="story" translationId="translation" findings={[{ id: "finding", review_id: "review", risk_category: "Identifying detail", proposal_summary: "A name may identify someone", suggested_safer_alternative: "A nearby town", translation_segment_id: "segment", translation_artifact_id: "translation", decision: null, passage: "A fictional name" }]} permissions={[]} covenantId={null} covenantApproved={false} eligible={false} />);
    expect(html).toContain("AI proposes potential concerns for your decision");
    expect(html).toContain("A fictional name");
    for (const decision of ["KEEP", "GENERALISE", "ANONYMISE", "REMOVE"]) expect(html).toContain(`>${decision}<`);
    expect(html).toContain("Not yet eligible");
    expect(html).toContain("Public viewing");
    expect(html).toContain("Voice cloning");
  });
});
