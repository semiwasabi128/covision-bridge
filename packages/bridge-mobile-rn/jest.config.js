module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  testMatch: ['**/tests/**/*.test.ts'],
  moduleNameMapper: {
    '^react$': '<rootDir>/tests/react-stub.js',
    '^react-native$': '<rootDir>/tests/react-native-stub.js',
  },
};
