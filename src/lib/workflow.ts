export const WORKFLOW_STAGES = [
  { id: "tell", label: "Tell", href: "/story/demo/tell" },
  { id: "verify", label: "Verify", href: "/story/demo/verify" },
  { id: "craft", label: "Craft", href: "/story/demo/craft" },
  { id: "translate", label: "Translate", href: "/story/demo/translate" },
  { id: "protect", label: "Protect", href: "/story/demo/protect" },
  { id: "publish", label: "Publish", href: "/story/demo/publish" },
] as const;

export type WorkflowStageId = (typeof WORKFLOW_STAGES)[number]["id"];

type OriginalLanguage = Readonly<{
  code: "yo";
  name: string;
}>;

type ShareLanguage = Readonly<{
  code: "en";
  name: string;
}>;

type DemoLanguageMetadata = Readonly<{
  original: Readonly<{
    detectionMode: "automatic";
    detected: OriginalLanguage;
    isDemonstration: true;
    storytellerConfirmed: false;
  }>;
  share: Readonly<{
    selected: ShareLanguage;
    functionalOptions: readonly ShareLanguage[];
    isDemonstration: true;
  }>;
}>;

export const DEMO_LANGUAGE_METADATA = {
  original: {
    detectionMode: "automatic",
    detected: { code: "yo", name: "Yoruba" },
    isDemonstration: true,
    storytellerConfirmed: false,
  },
  share: {
    selected: { code: "en", name: "English" },
    functionalOptions: [{ code: "en", name: "English" }],
    isDemonstration: true,
  },
} as const satisfies DemoLanguageMetadata;

export const MOCK_STORY = {
  title: "My Story",
  originalLanguage: DEMO_LANGUAGE_METADATA.original,
  shareLanguage: DEMO_LANGUAGE_METADATA.share,
  notice: "Static demonstration only. No story data or progress is saved.",
} as const;

export function getWorkflowStage(stageId: string | undefined) {
  return WORKFLOW_STAGES.find((stage) => stage.id === stageId);
}

export function getDemoStageParams() {
  return WORKFLOW_STAGES.map(({ id }) => ({ stage: id }));
}

