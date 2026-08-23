// ponytail: recommended rules only, no project-specific config until a real
// violation shows up worth codifying. This is the "lint" gate existing at
// all, not a style system.
import js from "@eslint/js";
import tseslint from "typescript-eslint";

export default tseslint.config(js.configs.recommended, tseslint.configs.recommended, {
  files: ["src/**/*.{ts,tsx}"],
});
