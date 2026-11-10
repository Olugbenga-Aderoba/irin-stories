import { redirect } from "next/navigation";

export const instant = false;

export default async function DemoStagePage({
  params,
}: { params: Promise<{ stage: string }> }) {
  await params;
  redirect("/workspace");
}

