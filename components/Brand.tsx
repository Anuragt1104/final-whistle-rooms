import Link from "next/link";

export function Brand({ small = false }: { small?: boolean }) {
  return (
    <Link href="/" className="flex items-center gap-2">
      <span className="grid place-items-center rounded-xl bg-[var(--color-lime)] text-[#0a1320] font-black shadow-[0_8px_20px_-10px_rgba(199,242,77,0.7)]"
        style={{ width: small ? 28 : 34, height: small ? 28 : 34 }}>
        ⚽
      </span>
      <span className="leading-none">
        <span className={`block font-extrabold tracking-tight ${small ? "text-sm" : "text-base"}`}>
          Final Whistle
        </span>
        {!small && (
          <span className="block text-[10px] uppercase tracking-[0.22em] text-[var(--color-mut)]">
            Rooms
          </span>
        )}
      </span>
    </Link>
  );
}
