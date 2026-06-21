export function pathname() {
  return globalThis.window?.location?.pathname ?? "/";
}
