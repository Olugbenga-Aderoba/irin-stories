import Link from "next/link";
import { BrandMark } from "@/components/brand-mark";

type SiteHeaderProps = {
  variant?: "marketing" | "workspace";
};

export function SiteHeader({ variant = "marketing" }: SiteHeaderProps) {
  if (variant === "workspace") {
    return (
      <header className="site-header site-header--workspace">
        <div className="site-header-inner mx-auto flex w-full max-w-7xl items-center justify-between px-5 sm:px-8">
          <Link className="brand-link" href="/" aria-label="Irin Stories home">
            <BrandMark />
          </Link>
          <div className="header-tools">
            <span className="demo-pill">
              <span aria-hidden="true" className="demo-pill-dot" />
              Demo workspace
            </span>
            <Link className="back-link" href="/">
              <span aria-hidden="true">←</span> Home
            </Link>
          </div>
        </div>
      </header>
    );
  }

  return (
    <header className="site-header">
      <div className="site-header-inner mx-auto flex w-full max-w-7xl items-center justify-between px-5 sm:px-8">
        <Link className="brand-link" href="/" aria-label="Irin Stories home">
          <BrandMark />
        </Link>
        <nav className="marketing-nav" aria-label="Main navigation">
          <a className="nav-text-link" href="#workflow">
            The process
          </a>
          <a className="nav-text-link" href="#principle">
            Our promise
          </a>
          <Link className="nav-cta" href="/story/demo/tell">
            Start your story <span aria-hidden="true">↗</span>
          </Link>
        </nav>
      </div>
    </header>
  );
}

