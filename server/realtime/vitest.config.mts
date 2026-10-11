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
          name: "integration",
          include: ["test/integration/**/*.test.ts"],
          environment: "node",
          testTimeout: 30_000,
          hookTimeout: 15_000,
        },
      },
      {
        // Needs the Firestore emulator: `npm run test:firestore` (uses the firebase CLI from
        // firebase/functions/node_modules or a global install).
        test: {
          name: "firestore",
          include: ["test/firestore/**/*.test.ts"],
          environment: "node",
          fileParallelism: false,
          testTimeout: 30_000,
        },
      },
    ],
  },
});
