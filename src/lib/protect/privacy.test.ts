import { describe, expect, it, vi } from "vitest";
import { canonicalProtectHash, createPrivacyReviewProvider } from "@/lib/protect/privacy";

const segment = { translationSegmentId: "11111111-1111-4111-8111-111111111111", text: "A fictional passage", startMs: 100, endMs: 900 };
describe("Protect privacy proposal contract", () => {
  it("accepts mocked AI findings only when they cite an exact supplied segment", async () => {
    const provider = createPrivacyReviewProvider(vi.fn().mockResolvedValue({ findings: [{ translationSegmentId: segment.translationSegmentId, riskCategory: "Identifying detail", affectedPassage: "A fictional passage", suggestedSaferAlternative: "A nearby town" }] }));
    await expect(provider([segment])).resolves.toHaveLength(1);
    const bad = createPrivacyReviewProvider(async () => ({ findings: [{ translationSegmentId: "22222222-2222-4222-8222-222222222222", riskCategory: "Other", affectedPassage: "passage", suggestedSaferAlternative: "" }] }));
    await expect(bad([segment])).rejects.toThrow("unknown segment");
  });
  it("hashes review provenance and payload deterministically", () => {
    const hash = canonicalProtectHash("privacy-review", { translation: "translation-a" }, []);
    expect(hash).toEqual(canonicalProtectHash("privacy-review", { translation: "translation-a" }, []));
    expect(hash).not.toEqual(canonicalProtectHash("privacy-review", { translation: "translation-b" }, []));
  });
});
