import { createHash } from "node:crypto";
import { z } from "zod";

export const privacyFindingSchema = z.object({
  translationSegmentId: z.string().uuid(),
  riskCategory: z.string().trim().min(1).max(80),
  affectedPassage: z.string().trim().min(1).max(2000),
  suggestedSaferAlternative: z.string().trim().max(2000),
}).strict();
export const privacyFindingsSchema = z.array(privacyFindingSchema).max(200);
export type PrivacyFindingInput = z.infer<typeof privacyFindingSchema>;

export const COVENANT_PERMISSION_KEYS = ["PUBLIC_VIEWING", "EDUCATIONAL_USE", "ACADEMIC_RESEARCH", "DOCUMENTARY_REUSE", "COMMERCIAL_REUSE", "AI_MODEL_TRAINING", "VOICE_CLONING", "POLITICAL_USE", "CHILD_IDENTITY_DISCLOSURE", "THIRD_PARTY_EDITING"] as const;
export type CovenantPermissionKey = typeof COVENANT_PERMISSION_KEYS[number];
export type CovenantPermissions = Record<CovenantPermissionKey, boolean>;

export function canonicalProtectHash(kind: "privacy-review" | "covenant", lineage: Record<string, string>, content: unknown) {
  return createHash("sha256").update(JSON.stringify({ kind, lineage, content }), "utf8").digest();
}

export function createPrivacyReviewProvider(completion: (segments: readonly { translationSegmentId: string; text: string; startMs: number; endMs: number }[]) => Promise<unknown>) {
  return async (segments: readonly { translationSegmentId: string; text: string; startMs: number; endMs: number }[]) => {
    const raw = await completion(segments);
    const parsed = z.object({ findings: privacyFindingsSchema }).strict().safeParse(raw);
    if (!parsed.success) throw new Error("Privacy findings could not be validated.");
    const allowed = new Set(segments.map((segment) => segment.translationSegmentId));
    if (parsed.data.findings.some((finding) => !allowed.has(finding.translationSegmentId))) throw new Error("Privacy finding referenced an unknown segment.");
    const textBySegment = new Map(segments.map((segment) => [segment.translationSegmentId, segment.text.toLocaleLowerCase()]));
    if (parsed.data.findings.some((finding) => !textBySegment.get(finding.translationSegmentId)?.includes(finding.affectedPassage.toLocaleLowerCase()))) throw new Error("Privacy finding passage was not present in its referenced segment.");
    return parsed.data.findings;
  };
}
