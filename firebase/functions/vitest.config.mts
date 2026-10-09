import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    projects: [
      {
        test: {
          name: "unit",
          include: ["test/unit/**/*.test.ts"],
          environment: "node",
        },
      },
      {
        test: {
          name: "emulator",
          include: ["test/emulator/**/*.test.ts"],
          environment: "node",
          // All emulator suites share one Firestore/Storage instance.
          fileParallelism: false,
          setupFiles: ["test/helpers/setupEmulator.ts"],
          testTimeout: 30_000,
          hookTimeout: 30_000,
        },
      },
    ],
  },
});
