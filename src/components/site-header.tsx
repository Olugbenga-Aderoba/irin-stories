import Link from "next/link";
import { BrandMark } from "@/components/brand-mark";
import { signOut } from "@/app/auth/actions";

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
            <Link className="back-link" href="/workspace">My stories</Link>
            <form action={signOut}><button className="back-link header-signout" type="submit">Sign out</button></form>
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
          <Link className="nav-cta" href="/sign-in">
            Start your story <span aria-hidden="true">↗</span>
          </Link>
        </nav>
      </div>
    </header>
  );
}

