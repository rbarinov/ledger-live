export default {
  preset: "ts-jest",
  globals: {
    "ts-jest": {
      isolatedModules: true,
    },
  },
  testEnvironment: "node",
  coverageDirectory: "./coverage/",
  coverageReporters: ["json", "lcov", "clover"],
  collectCoverage: true,
  coveragePathIgnorePatterns: ["src/__tests__"],
  modulePathIgnorePatterns: [
    "<rootDir>/benchmark/.*",
    "<rootDir>/cli/.yalc/.*",
  ],
  testPathIgnorePatterns: [
    "benchmark/",
    "tools/",
    "mobile-test-app/",
    "lib/",
    "lib-es/",
    ".yalc",
    "cli/",
    "test-helpers/",
  ],
  transformIgnorePatterns: ["/node_modules/(?!|@babel/runtime/helpers/esm/)"],
  moduleDirectories: ["node_modules", "cli/node_modules"],
};
