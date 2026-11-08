export function BrandMark({ compact = false }: { compact?: boolean }) {
  return (
    <span className={`brand-lockup${compact ? " brand-lockup--compact" : ""}`}>
      <svg
        aria-hidden="true"
        className="brand-mark"
        viewBox="0 0 40 40"
        fill="none"
      >
        <rect x="1" y="1" width="38" height="38" rx="14" fill="#243B32" />
        <path
          d="M10 23.5c4.8-7 9.3-7 14.1 0 2.1 3 4.1 3 6.2 0"
          stroke="#F6E7C9"
          strokeWidth="2.6"
          strokeLinecap="round"
        />
        <path
          d="M11 17.2c3.3-4.4 6.5-4.4 9.8 0 2.7 3.7 5.4 3.7 8.1 0"
          stroke="#E7825D"
          strokeWidth="2.6"
          strokeLinecap="round"
        />
      </svg>
      {!compact && (
        <span className="brand-wordmark">
          <span>Irin</span> Stories
        </span>
      )}
    </span>
  );
}

