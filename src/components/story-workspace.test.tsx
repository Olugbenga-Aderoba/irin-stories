import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { StoryWorkspace } from "@/components/story-workspace";

describe("story workspace language metadata", () => {
  it("shows the demo title, unconfirmed original-language example, and English-only share selection", () => {
    const markup = renderToStaticMarkup(<StoryWorkspace stageId="tell" />);

    expect(markup).toContain("<h1 id=\"story-title\">My Story</h1>");
    expect(markup).not.toContain(["The Market", "at Dawn"].join(" "));
    expect(markup).toContain("<dt>Original language</dt>");
    expect(markup).toContain("Detected: Yoruba");
    expect(markup).toContain("DEMO EXAMPLE · NOT CONFIRMED");
    expect(markup).toContain("Share my story in");
    expect(markup).toContain("<option value=\"en\" selected=\"\">English</option>");
    expect(markup).toContain("DEMO SELECTION · NOT SAVED");
    expect(markup).toContain("More languages can be added as Irin Stories grows.");
    expect(markup).not.toContain("Source language");
    expect(markup).not.toContain("Target language");

    const targetOptions = [...markup.matchAll(/<option\b[^>]*>(.*?)<\/option>/g)].map((match) => match[1]);
    expect(targetOptions).toEqual(["English"]);
  });
});
