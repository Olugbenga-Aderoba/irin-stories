import Link from "next/link";
import { WORKFLOW_STAGES, type WorkflowStageId } from "@/lib/workflow";

type WorkflowProgressProps = {
  currentStageId?: WorkflowStageId;
  demo?: boolean;
  className?: string;
};

export function WorkflowProgress({
  currentStageId,
  demo = false,
  className = "",
}: WorkflowProgressProps) {
  const currentIndex = currentStageId
    ? WORKFLOW_STAGES.findIndex((stage) => stage.id === currentStageId)
    : -1;

  return (
    <nav
      aria-label="Story workflow stages"
      className={`workflow-progress ${className}`.trim()}
    >
      <ol className="workflow-list">
        {WORKFLOW_STAGES.map((stage, index) => {
          const isCurrent = stage.id === currentStageId;
          const isComplete = currentIndex >= 0 && index < currentIndex;
          const status = isCurrent
            ? demo
              ? "Current example stage"
              : "Current stage"
            : isComplete
              ? demo
                ? "Example completed"
                : "Completed"
              : demo
                ? "Not started in demo"
                : "Upcoming";

          return (
            <li
              className="workflow-item"
              data-state={isCurrent ? "current" : isComplete ? "complete" : "future"}
              key={stage.id}
            >
              <Link
                aria-current={isCurrent ? "step" : undefined}
                aria-label={`${stage.label}: ${status}`}
                className="workflow-link"
                href={stage.href}
              >
                <span aria-hidden="true" className="workflow-marker">
                  {isComplete ? (
                    <svg viewBox="0 0 16 16" fill="none">
                      <path
                        d="m3.5 8.2 2.8 2.7 6.2-6.1"
                        stroke="currentColor"
                        strokeWidth="1.8"
                        strokeLinecap="round"
                        strokeLinejoin="round"
                      />
                    </svg>
                  ) : (
                    index + 1
                  )}
                </span>
                <span className="workflow-link-copy">
                  <span className="workflow-label">{stage.label}</span>
                  <span className="workflow-status">{status}</span>
                </span>
              </Link>
            </li>
          );
        })}
      </ol>
    </nav>
  );
}

