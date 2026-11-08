import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { WorkflowProgress } from "@/components/workflow-progress";

describe("WorkflowProgress", () => {
  it("marks completed, current, and future steps accessibly in the demo", () => {
    const markup = renderToStaticMarkup(
      <WorkflowProgress currentStageId="craft" demo />,
    );

    expect(markup).toContain('aria-label="Story workflow stages"');
    expect(markup).toContain('data-state="complete"');
    expect(markup).toContain('data-state="current"');
    expect(markup).toContain('data-state="future"');
    expect(markup).toContain('aria-current="step"');
    expect(markup).toContain('aria-label="Craft: Current example stage"');
    expect(markup).toContain("Example completed");
    expect(markup).toContain("Not started in demo");
  });

  it("provides keyboard-navigable links for every stage", () => {
    const markup = renderToStaticMarkup(<WorkflowProgress />);

    for (const stage of ["tell", "verify", "craft", "translate", "protect", "publish"]) {
      expect(markup).toContain(`href="/story/demo/${stage}"`);
    }
  });
});

