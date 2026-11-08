import Link from "next/link";
import { SiteHeader } from "@/components/site-header";
import { WorkflowProgress } from "@/components/workflow-progress";
import { DEMO_LANGUAGE_METADATA } from "@/lib/workflow";

function StoryArtwork() {
  return (
    <div
      className="hero-artwork"
      role="img"
      aria-label="Abstract paper illustration about a story travelling across borders"
    >
      <div className="artwork-topline">
        <span>ROOTED HERE</span>
        <span aria-hidden="true">✳</span>
        <span>MADE TO TRAVEL</span>
      </div>
      <div aria-hidden="true" className="artwork-sun" />
      <div aria-hidden="true" className="artwork-ring artwork-ring--outer" />
      <div aria-hidden="true" className="artwork-ring artwork-ring--inner" />
      <div aria-hidden="true" className="artwork-landscape">
        <span />
        <span />
        <span />
      </div>
      <div className="artwork-caption">
        <span className="artwork-caption-kicker">A story, held with care</span>
        <span className="artwork-caption-title">Yours to shape.<br />Ready to travel.</span>
      </div>
      <span className="artwork-index">IRIN · 01</span>
    </div>
  );
}

export function HomePage() {
  return (
    <div className="marketing-page">
      <a className="skip-link" href="#main-content">
        Skip to content
      </a>
      <SiteHeader />

      <main id="main-content">
        <section className="hero-section">
          <div className="hero-inner mx-auto grid w-full max-w-7xl items-center px-5 sm:px-8">
            <div className="hero-copy">
              <p className="eyebrow">
                <span aria-hidden="true" className="eyebrow-mark" />
                A storyteller-led studio
              </p>
              <h1>Your story begins in the language that feels like home.</h1>
              <p className="hero-tagline">African voices, across every border.</p>
              <p className="hero-description">
                Tell your story in your language. Shape it on your terms. Carry it across borders.
              </p>
              <p className="hero-detail">
                Irin Stories helps African storytellers shape authentic stories into culturally
                faithful, multilingual digital stories while keeping the storyteller in control.
              </p>
              <div className="hero-actions">
                <Link className="button button--primary" href="/story/demo/tell">
                  Start your story <span aria-hidden="true">↗</span>
                </Link>
                <span className="hero-action-note">Explore a static demo · uploads are not enabled</span>
              </div>
            </div>

            <div className="hero-visual-wrap">
              <div className="hero-visual-note hero-visual-note--top">
                <span className="note-dot note-dot--orange" />
                {DEMO_LANGUAGE_METADATA.original.detected.name} demo · {DEMO_LANGUAGE_METADATA.share.selected.name} subtitles
              </div>
              <StoryArtwork />
              <div className="hero-visual-note hero-visual-note--bottom">
                <span className="note-dot note-dot--green" />
                Shaped by the storyteller
              </div>
            </div>
          </div>
          <div aria-hidden="true" className="hero-bottom-rule" />
        </section>

        <section className="workflow-section" id="workflow" aria-labelledby="workflow-title">
          <div className="section-inner mx-auto w-full max-w-7xl px-5 sm:px-8">
            <div className="section-heading">
              <div>
                <p className="eyebrow">A clear path, with you at every step</p>
                <h2 id="workflow-title">From first telling to wider sharing.</h2>
              </div>
              <p className="section-intro">
                Each stage keeps your choices visible, your story grounded, and the next step in your hands.
              </p>
            </div>
            <WorkflowProgress className="workflow-progress--overview" />
          </div>
        </section>

        <section className="principle-section" id="principle" aria-labelledby="principle-title">
          <div className="principle-inner mx-auto grid w-full max-w-7xl items-center px-5 sm:px-8">
            <div className="principle-mark" aria-hidden="true">
              <span>“</span>
            </div>
            <div className="principle-copy">
              <p className="eyebrow eyebrow--light">The principle at the heart of Irin</p>
              <h2 id="principle-title">AI proposes.<br />The storyteller decides.</h2>
              <p>
                Suggestions stay suggestions until you choose what belongs in your story.
                Your voice, meaning, and approval lead the way.
              </p>
            </div>
            <div className="principle-aside">
              <span className="principle-aside-line" />
              <p>Human judgment<br />at every turn.</p>
            </div>
          </div>
        </section>

        <section className="closing-section">
          <div className="closing-inner mx-auto flex w-full max-w-7xl flex-col items-start justify-between px-5 sm:px-8">
            <div>
              <p className="eyebrow">Your story. Your terms.</p>
              <h2>Begin with what you want to say.</h2>
            </div>
            <Link className="button button--outline" href="/story/demo/tell">
              Start your story <span aria-hidden="true">↗</span>
            </Link>
          </div>
        </section>
      </main>

      <footer className="site-footer">
        <div className="footer-inner mx-auto flex w-full max-w-7xl items-center justify-between px-5 sm:px-8">
          <span className="footer-brand">Irin Stories</span>
          <span>African voices, across every border.</span>
          <span className="footer-demo">Static prototype</span>
        </div>
      </footer>
    </div>
  );
}

