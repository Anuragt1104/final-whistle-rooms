// Stub for next/link used only by design-sync previews/bundle — renders a
// plain anchor so components that link (Brand, FixtureRow) render outside a
// Next.js app-router context.
import * as React from "react";

const Link = React.forwardRef<HTMLAnchorElement, any>(function Link(
  { href, children, ...rest },
  ref
) {
  const url = typeof href === "string" ? href : href?.pathname ?? "#";
  return (
    <a ref={ref} href={url} {...rest}>
      {children}
    </a>
  );
});
export default Link;
