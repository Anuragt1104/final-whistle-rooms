// Stub for next/navigation used only by design-sync previews/bundle. The
// excluded page-level clients import these at module scope; their hooks never
// fire in previews (those components are not rendered as cards).
const noop = () => {};
export function useRouter() {
  return { push: noop, replace: noop, back: noop, forward: noop, refresh: noop, prefetch: noop };
}
export function useSearchParams() {
  return new URLSearchParams();
}
export function usePathname() {
  return "/";
}
export function useParams() {
  return {} as Record<string, string>;
}
export function redirect(_url: string): never {
  throw new Error("redirect (stub)");
}
export function notFound(): never {
  throw new Error("notFound (stub)");
}
