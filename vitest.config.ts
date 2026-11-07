import { defineConfig } from "vitest/config";

// There are no tests here yet; this file keeps the folder in step with the
// rest of the collection so vitest can be adopted file by file.
export default defineConfig({
  test: {
    environment: "happy-dom",
    globals: true,
    passWithNoTests: true,
  },
});
