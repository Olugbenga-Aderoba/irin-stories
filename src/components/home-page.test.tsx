import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { HomePage } from "@/components/home-page";

describe("home page", () => {
  it("renders the Irin Stories message, workflow, principle, and demo CTA", () => {
    const markup = renderToStaticMarkup(<HomePage />);

    expect(markup).toContain("Irin");
    expect(markup).toContain("African voices, across every border.");
    expect(markup).toContain("Tell your story in your language.");
    expect(markup).toContain("Start your story");
    expect(markup).toContain('href="/story/demo/tell"');
    expect(markup).toContain("AI proposes.");
    expect(markup).toContain("The storyteller decides.");
    expect(markup).toContain("Yoruba demo · English subtitles");
    expect(markup).toContain("uploads are not enabled");
    expect(markup).not.toContain("To get started, edit");
  });
});

