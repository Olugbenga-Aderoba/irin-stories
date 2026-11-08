import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { StagePlaceholder } from "@/components/stage-placeholders";
import { WORKFLOW_STAGES } from "@/lib/workflow";

describe("stage placeholders", () => {
  it("renders a clearly static view for every workflow route", () => {
    for (const stage of WORKFLOW_STAGES) {
      const markup = renderToStaticMarkup(<StagePlaceholder stageId={stage.id} />);
      expect(markup.length).toBeGreaterThan(0);
    }
  });

  it("keeps Tell and Verify controls disabled and marked as examples", () => {
    const tellMarkup = renderToStaticMarkup(<StagePlaceholder stageId="tell" />);
    expect(tellMarkup).toContain("Begin with your authentic story");
    expect(tellMarkup).toContain("Original language");
    expect(tellMarkup).not.toContain("Source language");
    expect(tellMarkup).toContain("Detect automatically");
    expect(tellMarkup).toContain("DETECTED LANGUAGE · EXAMPLE ONLY");
    expect(tellMarkup).toContain("Detected language: Yoruba");
    expect(tellMarkup).toContain("Automatic language detection is not implemented");
    expect(tellMarkup).toContain("Is Yoruba correct?");
    expect(tellMarkup).toContain("Yes, continue");
    expect(tellMarkup).toContain("Change language");
    expect(tellMarkup).toContain("AI proposes. The storyteller decides.");
    expect(tellMarkup).toContain("Upload your story");
    expect(tellMarkup).toContain("disabled=\"\"");
    expect(tellMarkup).toContain("Upload is not available in this static prototype.");

    const verifyMarkup = renderToStaticMarkup(<StagePlaceholder stageId="verify" />);
    expect(verifyMarkup).toContain("Transcript review");
    expect(verifyMarkup).toContain("00:12");
    expect(verifyMarkup).toContain("Approve Yoruba Source");
    expect(verifyMarkup).toContain("No transcript is being reviewed or approved.");
  });

  it("shows source-traced cut examples and bilingual translation examples", () => {
    const craftMarkup = renderToStaticMarkup(<StagePlaceholder stageId="craft" />);
    expect(craftMarkup).toContain("02:15");
    expect(craftMarkup).toContain("Opening image");
    expect(craftMarkup).toContain("Reorder");
    expect(craftMarkup).toContain("no video edit has been created");

    const translateMarkup = renderToStaticMarkup(<StagePlaceholder stageId="translate" />);
    expect(translateMarkup).toContain("YORUBA ORIGINAL");
    expect(translateMarkup).toContain("ENGLISH TRANSLATION");
    expect(translateMarkup).toContain("Literal meaning");
    expect(translateMarkup).toContain("Example storyteller interpretation");
    expect(translateMarkup).toContain("fictional example content");
  });

  it("shows the four non-functional privacy decisions and illustrative publication states", () => {
    const protectMarkup = renderToStaticMarkup(<StagePlaceholder stageId="protect" />);
    for (const decision of ["Keep", "Generalise", "Anonymise", "Remove"]) {
      expect(protectMarkup).toContain(`>${decision}</button>`);
    }
    expect(protectMarkup).toContain("AI training");
    expect(protectMarkup).toContain("Voice cloning");
    expect(protectMarkup).toContain("not a real Covenant");

    const publishMarkup = renderToStaticMarkup(<StagePlaceholder stageId="publish" />);
    expect(publishMarkup).toContain("Yoruba original");
    expect(publishMarkup).toContain("English subtitles available");
    expect(publishMarkup).toContain("Verified Publication");
    expect(publishMarkup).toContain("No approval, privacy review, Covenant, or verification has occurred");
    expect(publishMarkup).toContain("QR-code placeholder, not scannable");
    expect(publishMarkup).toContain("My Story");
    expect(publishMarkup).not.toContain(["The Market", "at Dawn"].join(" "));
  });

  it("labels the Craft working title as an ungenerated suggestion that needs approval", () => {
    const craftMarkup = renderToStaticMarkup(<StagePlaceholder stageId="craft" />);

    expect(craftMarkup).toContain("FUTURE AI WORKING TITLE SUGGESTION · EXAMPLE ONLY");
    expect(craftMarkup).toContain("No AI generated or selected this title");
    expect(craftMarkup).toContain("the storyteller must approve any title change");
    expect(craftMarkup).toContain("No suggestion was generated");
    expect(craftMarkup).toContain("disabled=\"\"");
  });
});

