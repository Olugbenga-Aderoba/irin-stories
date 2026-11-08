import { createElement, type AnchorHTMLAttributes } from "react";
import { vi } from "vitest";

vi.mock("next/link", () => ({
  default: function MockLink({
    href,
    ...props
  }: AnchorHTMLAttributes<HTMLAnchorElement> & { href: string }) {
    return createElement("a", { href, ...props });
  },
}));

