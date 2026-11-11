import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { PublicationReview, PublicStoryCard } from "@/components/publication-review";

describe("Publish and withdrawal UI", () => {
  it("requires eligibility and presents final approval separately from Publish", () => {
    const blocked = renderToStaticMarkup(<PublicationReview storyId="story" eligible={false} snapshotId={null} publicId={null} state={null} approved={false} />);
    expect(blocked).toContain("Not yet eligible"); expect(blocked).toContain("disabled");
    const review = renderToStaticMarkup(<PublicationReview storyId="story" eligible snapshotId="snapshot" publicId="public" state="DRAFT" approved={false} />);
    expect(review).toContain("Approve this publication"); expect(review).not.toContain(">Publish now<");
    const ready = renderToStaticMarkup(<PublicationReview storyId="story" eligible snapshotId="snapshot" publicId="public" state="DRAFT" approved />);
    expect(ready).toContain("Publish now"); expect(ready).toContain("Publication has not started");
  });
  it("explains withdrawal and exposes only public RPC fields", () => {
    const owner = renderToStaticMarkup(<PublicationReview storyId="story" eligible snapshotId="snapshot" publicId="public" state="PUBLISHED" approved />);
    expect(owner).toContain("Withdraw publication"); expect(owner).toContain("cannot be recalled");
    const page = renderToStaticMarkup(<PublicStoryCard story={{ public_id: "public", title: "A Story", original_language_code: "yor", share_language_code: "eng", ai_editing_disclosed: true, ai_translation_disclosed: true, published_at: "2026-11-11T12:00:00Z" }} />);
    expect(page).toContain("A Story"); expect(page).toContain("AI-assisted English translation disclosed"); expect(page).not.toContain("owner_id");
  });
});
