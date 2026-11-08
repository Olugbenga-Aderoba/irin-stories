import { notFound } from "next/navigation";
import { StoryWorkspace } from "@/components/story-workspace";
import { getDemoStageParams, getWorkflowStage } from "@/lib/workflow";

export function generateStaticParams() {
  return getDemoStageParams();
}

export default async function DemoStagePage({
  params,
}: {
  params: Promise<{ stage: string }>;
}) {
  const { stage: stageId } = await params;
  const stage = getWorkflowStage(stageId);

  if (!stage) {
    notFound();
  }

  return <StoryWorkspace stageId={stage.id} />;
}

