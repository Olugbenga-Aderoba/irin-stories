import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Irin Stories",
  description:
    "Tell your story in your language. Shape it on your terms. Carry it across borders.",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" className="h-full antialiased">
      <body className="min-h-full flex flex-col">{children}</body>
    </html>
  );
}
