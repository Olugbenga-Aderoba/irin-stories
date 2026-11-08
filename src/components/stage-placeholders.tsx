import type { ReactNode } from "react";
import { MOCK_STORY, type WorkflowStageId } from "@/lib/workflow";

function DemoNote({ children = "Demonstration only · no action is saved" }: { children?: ReactNode }) {
  return (
    <p className="demo-note">
      <span aria-hidden="true" className="demo-note-icon">i</span>
      {children}
    </p>
  );
}

function VideoPlaceholder({ compact = false }: { compact?: boolean }) {
  return (
    <div
      className={`video-placeholder${compact ? " video-placeholder--compact" : ""}`}
      role="img"
      aria-label="Illustrative video preview placeholder. No video has been uploaded."
    >
      <div aria-hidden="true" className="video-art-sun" />
      <div aria-hidden="true" className="video-art-hill video-art-hill--back" />
      <div aria-hidden="true" className="video-art-hill video-art-hill--front" />
      <span aria-hidden="true" className="video-play-mark">▶</span>
      <span className="video-placeholder-label">VIDEO PREVIEW · DEMO ONLY</span>
    </div>
  );
}

function DisabledAction({ children }: { children: ReactNode }) {
  return (
    <button className="button button--quiet" type="button" disabled>
      {children}
    </button>
  );
}

function TellPlaceholder() {
  const detectedLanguage = MOCK_STORY.originalLanguage.detected;

  return (
    <div className="stage-content-grid stage-content-grid--tell">
      <VideoPlaceholder />
      <div className="stage-side-panel">
        <section className="language-detection-card" aria-labelledby="original-language-title">
          <div className="language-detection-heading">
            <div>
              <span className="field-label">Original language</span>
              <h3 id="original-language-title">Detect automatically</h3>
            </div>
            <span className="example-tag">Demo state</span>
          </div>
          <div className="detected-language-example">
            <span className="field-label">DETECTED LANGUAGE · EXAMPLE ONLY</span>
            <p lang={detectedLanguage.code}>Detected language: {detectedLanguage.name}</p>
          </div>
          <div className="language-confirmation-example">
            <h4>Is {detectedLanguage.name} correct?</h4>
            <p>AI proposes. The storyteller decides.</p>
            <div className="language-confirmation-actions">
              <button className="button button--primary" type="button" disabled>
                Yes, continue
              </button>
              <DisabledAction>Change language</DisabledAction>
            </div>
          </div>
          <DemoNote>
            Automatic language detection is not implemented. This is a demonstration example, not a live detection. {detectedLanguage.name} is the only original language supported in this hackathon MVP.
          </DemoNote>
        </section>
        <p className="stage-lead">
          Begin with your authentic story in the language that feels natural to you.
        </p>
        <div className="upload-placeholder">
          <span aria-hidden="true" className="upload-icon">↑</span>
          <span className="upload-placeholder-title">Your video will live here</span>
          <span className="upload-placeholder-detail">One private story, told your way.</span>
        </div>
        <DisabledAction>Upload your story</DisabledAction>
        <DemoNote>Upload is not available in this static prototype.</DemoNote>
      </div>
    </div>
  );
}

const transcriptLines = [
  { time: "00:12", text: "Nígbà tí mo dé sí ọjà ní òwúrọ̀…", state: "Reviewed example" },
  { time: "00:38", text: "A máa ń ran ara wa lọ́wọ́ níbí.", state: "Needs your review" },
  { time: "01:08", text: "Ohun tí mo rántí jù ni…", state: "Needs your review" },
];

function VerifyPlaceholder() {
  return (
    <div className="stage-content-stack">
      <VideoPlaceholder compact />
      <section className="transcript-card" aria-labelledby="transcript-title">
        <div className="card-heading-row">
          <div>
          <span className="field-label">{MOCK_STORY.originalLanguage.detected.name.toUpperCase()} ORIGINAL</span>
            <h3 id="transcript-title">Transcript review</h3>
          </div>
          <span className="example-progress">1 of 3 reviewed · example</span>
        </div>
        <div className="transcript-list">
          {transcriptLines.map((line) => (
            <article className="transcript-line" key={line.time}>
              <span className="timestamp">{line.time}</span>
              <p lang={MOCK_STORY.originalLanguage.detected.code}>{line.text}</p>
              <span className={`review-state${line.state === "Reviewed example" ? " review-state--done" : ""}`}>
                {line.state}
              </span>
            </article>
          ))}
        </div>
        <div className="placeholder-actions" aria-describedby="verify-actions-note">
          <DisabledAction>Edit</DisabledAction>
          <DisabledAction>Restore</DisabledAction>
          <DisabledAction>Reviewed</DisabledAction>
          <button className="button button--primary" type="button" disabled>
            Approve {MOCK_STORY.originalLanguage.detected.name} Source
          </button>
        </div>
        <p className="demo-note" id="verify-actions-note">
          These are conceptual controls. No transcript is being reviewed or approved.
        </p>
      </section>
    </div>
  );
}

const cutSegments = [
  {
    time: "00:18–00:42",
    role: "Opening image",
    reason: "Introduces the morning market before the story unfolds.",
  },
  {
    time: "04:10–04:44",
    role: "Turning point",
    reason: "Shows the moment neighbors begin helping one another.",
  },
  {
    time: "08:02–09:19",
    role: "Closing thought",
    reason: "Returns to what the storyteller wants the audience to remember.",
  },
];

function CraftPlaceholder() {
  return (
    <div className="stage-content-stack">
      <section className="title-suggestion-card" aria-labelledby="title-suggestion-heading">
        <div>
          <span className="field-label">FUTURE AI WORKING TITLE SUGGESTION · EXAMPLE ONLY</span>
          <h3 id="title-suggestion-heading">A Morning Shared</h3>
          <p>
            Illustrative suggestion only. No AI generated or selected this title; the storyteller must approve any title change.
          </p>
        </div>
        <DisabledAction>Approve title suggestion</DisabledAction>
      </section>
      <DemoNote>The story remains “{MOCK_STORY.title}” unless the storyteller chooses otherwise. No suggestion was generated.</DemoNote>
      <div className="cut-summary-card">
        <div>
          <span className="field-label">CONCEPTUAL STORY CUT</span>
          <h3>A beginning, a turn, a thought to carry.</h3>
        </div>
        <div className="duration-block">
          <span className="duration-value">02:15</span>
          <span className="duration-label">estimated duration</span>
        </div>
      </div>
      <div className="cut-segment-list">
        {cutSegments.map((segment, index) => (
          <article className="cut-segment" key={segment.time}>
            <div className="cut-segment-number" aria-hidden="true">0{index + 1}</div>
            <div className="cut-segment-main">
              <div className="cut-segment-topline">
                <span className="timestamp">{segment.time}</span>
                <span className="segment-role">{segment.role}</span>
              </div>
              <p>{segment.reason}</p>
              <span className="why-label">Why this segment · example note</span>
              <div className="segment-actions" aria-label={`Conceptual actions for ${segment.role}`}>
                <DisabledAction>Keep</DisabledAction>
                <DisabledAction>Remove</DisabledAction>
                <DisabledAction>Restore</DisabledAction>
                <DisabledAction>Reorder</DisabledAction>
              </div>
            </div>
          </article>
        ))}
      </div>
      <DemoNote>Segments and duration are static examples; no video edit has been created.</DemoNote>
    </div>
  );
}

function TranslatePlaceholder() {
  const originalLanguage = MOCK_STORY.originalLanguage.detected;
  const shareLanguage = MOCK_STORY.shareLanguage.selected;

  return (
    <div className="stage-content-stack">
      <div className="translation-grid">
        <section className="translation-card translation-card--source" aria-labelledby="original-text-title">
          <span className="field-label">{originalLanguage.name.toUpperCase()} ORIGINAL</span>
          <h3 id="original-text-title">A line from the telling</h3>
          <span className="timestamp">00:38–00:42 · example</span>
          <p className="language-quote" lang={originalLanguage.code}>A máa ń ran ara wa lọ́wọ́ níbí.</p>
          <span className="translation-card-foot">Source text · static example</span>
        </section>
        <section className="translation-card translation-card--target" aria-labelledby="share-translation-title">
          <span className="field-label">{shareLanguage.name.toUpperCase()} TRANSLATION</span>
          <h3 id="share-translation-title">A subtitle, shaped with care</h3>
          <span className="timestamp">00:38–00:42 · example</span>
          <p className="language-quote" lang={shareLanguage.code}>We help one another here.</p>
          <span className="translation-card-foot">Draft example · not approved</span>
        </section>
      </div>
      <section className="culture-example" aria-labelledby="culture-example-title">
        <div className="culture-example-heading">
          <span className="culture-flower" aria-hidden="true">✳</span>
          <div>
            <span className="field-label">CULTURAL EXPRESSION · FICTIONAL EXAMPLE</span>
            <h3 id="culture-example-title" lang={originalLanguage.code}>Ọ̀nà kan ò wọ ọjà.</h3>
          </div>
        </div>
        <dl className="culture-meaning-grid">
          <div>
            <dt>Literal meaning</dt>
            <dd>“One road does not enter the market.”</dd>
          </div>
          <div>
            <dt>Contextual meaning</dt>
            <dd>There can be more than one way to reach a goal.</dd>
          </div>
          <div className="culture-meaning-featured">
            <dt>Example storyteller interpretation</dt>
            <dd>“When one path is blocked, ask your neighbors what other way they know.”</dd>
          </div>
        </dl>
        <DemoNote>This interpretation is fictional example content and needs a storyteller’s review.</DemoNote>
      </section>
      <DemoNote>Translation and cultural notes are static examples; nothing has been translated or approved.</DemoNote>
    </div>
  );
}

const covenantExamples = [
  { permission: "Public viewing", example: "Demo preview only" },
  { permission: "Educational reuse", example: "Ask first · example" },
  { permission: "Commercial reuse", example: "Not granted · example" },
  { permission: "AI training", example: "Not granted · example" },
  { permission: "Voice cloning", example: "Never permitted" },
];

function ProtectPlaceholder() {
  return (
    <div className="stage-content-stack">
      <section className="finding-card" aria-labelledby="finding-title">
        <div className="finding-icon" aria-hidden="true">!</div>
        <div className="finding-copy">
          <span className="field-label">POTENTIAL PRIVACY CONCERN · FICTIONAL</span>
          <h3 id="finding-title">A sample line may reveal a precise location.</h3>
          <p>
            Example at 01:08: a street name and house number appear in the transcript sample.
            This is not a real person or address.
          </p>
          <div className="decision-actions" aria-label="Conceptual privacy decisions">
            <DisabledAction>Keep</DisabledAction>
            <DisabledAction>Generalise</DisabledAction>
            <DisabledAction>Anonymise</DisabledAction>
            <DisabledAction>Remove</DisabledAction>
          </div>
          <DemoNote>AI has not reviewed any media. The storyteller’s decision would be required.</DemoNote>
        </div>
      </section>

      <section className="covenant-card" aria-labelledby="covenant-title">
        <div className="card-heading-row">
          <div>
            <span className="field-label">STORY COVENANT PREVIEW</span>
            <h3 id="covenant-title">Your permissions, in your words.</h3>
          </div>
          <span className="example-tag">EXAMPLE ONLY</span>
        </div>
        <dl className="permission-list">
          {covenantExamples.map((item) => (
            <div className="permission-row" key={item.permission}>
              <dt>{item.permission}</dt>
              <dd>{item.example}</dd>
            </div>
          ))}
        </dl>
        <DemoNote>These sample permissions are not a real Covenant and have not been accepted or saved.</DemoNote>
      </section>
    </div>
  );
}

function QrPlaceholder() {
  return (
    <div className="qr-placeholder" role="img" aria-label="QR-code placeholder, not scannable">
      <span aria-hidden="true" className="qr-finder qr-finder--top-left" />
      <span aria-hidden="true" className="qr-finder qr-finder--top-right" />
      <span aria-hidden="true" className="qr-finder qr-finder--bottom-left" />
      <span aria-hidden="true" className="qr-pixels" />
      <span className="qr-caption">NOT SCANNABLE</span>
    </div>
  );
}

function PublishPlaceholder() {
  const originalLanguage = MOCK_STORY.originalLanguage.detected;
  const shareLanguage = MOCK_STORY.shareLanguage.selected;

  return (
    <div className="stage-content-stack">
      <div className="publication-preview-note">
        <span aria-hidden="true">✳</span>
        Conceptual publication preview · all data and statuses are illustrative only
      </div>
      <article className="publication-card" aria-labelledby="publication-title">
        <div className="publication-media">
          <VideoPlaceholder compact />
        </div>
        <div className="publication-body">
          <div className="publication-heading">
            <div>
              <span className="field-label">A STORY FROM {originalLanguage.name.toUpperCase()} · DEMO</span>
              <h3 id="publication-title">{MOCK_STORY.title}</h3>
            </div>
            <span className="verified-badge"><span aria-hidden="true">✓</span> Verified Publication</span>
          </div>
          <div className="publication-language-row">
            <span>{originalLanguage.name} original</span>
            <span className="language-divider" aria-hidden="true">→</span>
            <span>{shareLanguage.name} subtitles available</span>
          </div>
          <div className="publication-status-list" aria-label="Illustrative publication statuses">
            <span className="status-chip"><span aria-hidden="true">✓</span> Storyteller Approved</span>
            <span className="status-chip"><span aria-hidden="true">✓</span> Privacy Reviewed</span>
            <span className="status-chip"><span aria-hidden="true">✓</span> Story Covenant Active</span>
          </div>
          <p className="publication-disclosure">
            Illustrative status only. No approval, privacy review, Covenant, or verification has occurred.
          </p>
        </div>
        <div className="publication-qr-wrap">
          <QrPlaceholder />
          <span>Share card placeholder</span>
        </div>
      </article>
      <DemoNote>No story is published, verified, or available at a public URL.</DemoNote>
    </div>
  );
}

export function StagePlaceholder({ stageId }: { stageId: WorkflowStageId }) {
  switch (stageId) {
    case "tell":
      return <TellPlaceholder />;
    case "verify":
      return <VerifyPlaceholder />;
    case "craft":
      return <CraftPlaceholder />;
    case "translate":
      return <TranslatePlaceholder />;
    case "protect":
      return <ProtectPlaceholder />;
    case "publish":
      return <PublishPlaceholder />;
  }
}

