import { SiteHeader } from "@/components/site-header";
import { StagePlaceholder } from "@/components/stage-placeholders";
import { WorkflowProgress } from "@/components/workflow-progress";
import { MOCK_STORY, WORKFLOW_STAGES, type WorkflowStageId } from "@/lib/workflow";

const originalLanguageName = MOCK_STORY.originalLanguage.detected.name;
const shareLanguageName = MOCK_STORY.shareLanguage.selected.name;

const stageCopy: Record<WorkflowStageId, { title: string; description: string }> = {
  tell: {
    title: "Tell your story",
    description: "Start in the language that feels natural to you.",
  },
  verify: {
    title: "Review what was heard",
    description: `Shape the ${originalLanguageName} transcript before anything moves forward.`,
  },
  craft: {
    title: "Shape the Story Cut",
    description: "Choose the moments that carry your story, in your order.",
  },
  translate: {
    title: "Carry the meaning across",
    description: `Review each ${shareLanguageName} subtitle against the ${originalLanguageName} original.`,
  },
  protect: {
    title: "Decide what stays private",
    description: "Review each concern and choose what happens next.",
  },
  publish: {
    title: "Your story, ready to travel",
    description: "Review the final story and its permissions before sharing.",
  },
};

export function StoryWorkspace({ stageId }: { stageId: WorkflowStageId }) {
  const stageIndex = WORKFLOW_STAGES.findIndex((stage) => stage.id === stageId);
  const stage = WORKFLOW_STAGES[stageIndex];
  const copy = stageCopy[stageId];

  return (
    <div className="workspace-page">
      <a className="skip-link" href="#workspace-main">
        Skip to workspace
      </a>
      <SiteHeader variant="workspace" />
      <main className="workspace-main mx-auto w-full max-w-7xl px-5 sm:px-8" id="workspace-main">
        <div className="workspace-demo-banner" role="note">
          <span className="demo-banner-icon" aria-hidden="true">✳</span>
          <div>
            <strong>Static demo workspace</strong>
            <span>{MOCK_STORY.notice}</span>
          </div>
        </div>

        <section className="workspace-story-heading" aria-labelledby="story-title">
          <div className="workspace-story-title">
            <p className="eyebrow">STORY · STATIC DEMO</p>
            <h1 id="story-title">{MOCK_STORY.title}</h1>
            <p>Working title · demonstration only</p>
          </div>
          <dl className="story-meta-list">
            <div className="story-meta-language story-meta-original">
              <dt>Original language</dt>
              <dd>
                <span className="language-dot" aria-hidden="true" />
                Detected: {MOCK_STORY.originalLanguage.detected.name}
              </dd>
              <p className="story-meta-note">DEMO EXAMPLE · NOT CONFIRMED</p>
            </div>
            <div className="story-meta-language story-meta-target">
              <dt id="share-language-label">Share my story in</dt>
              <dd>
                <div className="language-select-wrap">
                  <select
                    aria-describedby="share-language-note"
                    aria-labelledby="share-language-label"
                    className="language-select"
                    defaultValue={MOCK_STORY.shareLanguage.selected.code}
                    disabled
                    id="share-target-language"
                  >
                    {MOCK_STORY.shareLanguage.functionalOptions.map((language) => (
                      <option key={language.code} value={language.code}>
                        {language.name}
                      </option>
                    ))}
                  </select>
                  <span aria-hidden="true" className="language-select-chevron">⌄</span>
                </div>
                <span className="language-select-status">DEMO SELECTION · NOT SAVED</span>
              </dd>
              <p className="story-meta-note" id="share-language-note">
                {MOCK_STORY.shareLanguage.selected.name} is the only language available to share in this hackathon MVP.
                More languages can be added as Irin Stories grows.
              </p>
            </div>
            <div className="story-meta-current">
              <dt>Current demo stage</dt>
              <dd><span className="current-step-dot" aria-hidden="true" />{stage.label}</dd>
            </div>
          </dl>
        </section>

        <section className="workspace-progress-card" aria-labelledby="progress-title">
          <div className="workspace-progress-heading">
            <div>
              <p className="eyebrow">THE STORY PATH</p>
              <h2 id="progress-title">One step at a time.</h2>
            </div>
            <span className="progress-count">Example step {stageIndex + 1} of {WORKFLOW_STAGES.length}</span>
          </div>
          <WorkflowProgress currentStageId={stageId} demo />
        </section>

        <section className="stage-panel" aria-labelledby="stage-title">
          <div className="stage-panel-heading">
            <div>
              <span className="stage-number">STEP {String(stageIndex + 1).padStart(2, "0")} · {stage.label.toUpperCase()}</span>
              <h2 id="stage-title">{copy.title}</h2>
              <p>{copy.description}</p>
            </div>
            <span className="placeholder-chip">Placeholder</span>
          </div>
          <StagePlaceholder stageId={stageId} />
          <div className="stage-panel-footnote">
            <span aria-hidden="true">✳</span>
            <span>Every screen here is an illustration. Controls are disabled and no work is saved.</span>
          </div>
        </section>
        <footer className="workspace-footer">
          <span>Irin Stories</span>
          <span>AI proposes. The storyteller decides.</span>
        </footer>
      </main>
    </div>
  );
}

