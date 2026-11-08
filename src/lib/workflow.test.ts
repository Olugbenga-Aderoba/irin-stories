import { describe, expect, it } from "vitest";
import {
  DEMO_LANGUAGE_METADATA,
  getDemoStageParams,
  getWorkflowStage,
  MOCK_STORY,
  WORKFLOW_STAGES,
} from "@/lib/workflow";

describe("story workflow definition", () => {
  it("keeps the six MVP stages in product order", () => {
    expect(WORKFLOW_STAGES.map((stage) => stage.label)).toEqual([
      "Tell",
      "Verify",
      "Craft",
      "Translate",
      "Protect",
      "Publish",
    ]);
  });

  it("maps every stage to its demo route", () => {
    expect(WORKFLOW_STAGES.map((stage) => stage.href)).toEqual([
      "/story/demo/tell",
      "/story/demo/verify",
      "/story/demo/craft",
      "/story/demo/translate",
      "/story/demo/protect",
      "/story/demo/publish",
    ]);
    expect(getDemoStageParams()).toEqual([
      { stage: "tell" },
      { stage: "verify" },
      { stage: "craft" },
      { stage: "translate" },
      { stage: "protect" },
      { stage: "publish" },
    ]);
  });

  it("returns no stage for an unknown route segment", () => {
    expect(getWorkflowStage("upload")).toBeUndefined();
  });

  it("keeps the demo title and language model centralized and within MVP scope", () => {
    expect(MOCK_STORY.title).toBe("My Story");
    expect(DEMO_LANGUAGE_METADATA.original).toMatchObject({
      detectionMode: "automatic",
      detected: { code: "yo", name: "Yoruba" },
      isDemonstration: true,
      storytellerConfirmed: false,
    });
    expect(DEMO_LANGUAGE_METADATA.share).toMatchObject({
      selected: { code: "en", name: "English" },
      isDemonstration: true,
    });
    expect(DEMO_LANGUAGE_METADATA.share.functionalOptions).toEqual([
      DEMO_LANGUAGE_METADATA.share.selected,
    ]);
  });
});

