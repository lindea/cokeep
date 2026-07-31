# Testing & CI/CD Guide

This document describes how to run tests and set up continuous integration for CoKeep.

## Table of Contents
- [Backend Testing (Node.js)](#backend-testing-nodejs)
- [iOS Testing (SwiftUI)](#ios-testing-swiftui)
- [GitHub Actions CI](#github-actions-ci)
- [Xcode Cloud](#xcode-cloud)
- [Heroku CI](#heroku-ci)

---

## Backend Testing (Node.js)

### Running Tests Locally

```bash
cd backend
npm test
```

The backend uses Node.js native test runner (`node:test`). Tests are located in `*.test.ts` files alongside the code they test.

### Test Structure

```typescript
import test from "node:test";
import assert from "node:assert/strict";

test("description", async (t) => {
  await t.test("sub-test", () => {
    assert.equal(actual, expected);
  });
});
```

### Current Test Coverage

- ✅ `src/utils/helpers.test.ts` - Helper functions
- ✅ `src/utils/dueDates.test.ts` - Due date calculations
- ✅ `src/routes/todos.test.ts` - Todo and photo endpoint validation

### Adding New Tests

1. Create a `*.test.ts` file next to the code you're testing
2. Import `test` and `assert` from Node.js
3. Write test cases using `test()` function
4. Run `npm test` to verify

---

## iOS Testing (SwiftUI)

### Test Target Setup

The project includes a `CoKeepTests` target with unit tests for:
- Date formatting functions
- Duration formatting
- Date range formatting
- Model validation

### Running Tests in Xcode

1. Open `ios/CoKeep/CoKeep.xcodeproj` in Xcode
2. Select the `CoKeepTests` scheme
3. Press `Cmd+U` to run all tests
4. View results in the Test Navigator (`Cmd+6`)

### Test File Location

```
ios/CoKeep/CoKeepTests/
├── TodoViewModelTests.swift    # Tests for todo-related logic
└── Info.plist                  # Test bundle configuration
```

### Adding New iOS Tests

1. Right-click `CoKeepTests` folder in Xcode
2. Select "New File" → "Unit Test Case Class"
3. Import your app module: `@testable import CoKeep`
4. Write test methods starting with `test`

```swift
import XCTest
@testable import CoKeep

final class MyTests: XCTestCase {
    func testExample() {
        XCTAssertEqual(1 + 1, 2)
    }
}
```

---

## GitHub Actions CI

### Backend Tests Workflow

Location: `.github/workflows/backend-tests.yml`

**Triggers:**
- Push to `cursor/cokeep-maintenance-app-72f3` branch
- Pull requests targeting `cursor/cokeep-maintenance-app-72f3`
- Only when `backend/` files change

**What it does:**
1. Sets up Node.js (versions 20.x and 22.x matrix)
2. Starts PostgreSQL 16 service
3. Installs dependencies
4. Runs Prisma migrations
5. Executes all tests
6. Reports results

**Environment Variables Needed:**
- `DATABASE_URL` - Auto-configured for CI
- `JWT_SECRET` - Set to `test-secret-key-for-ci`
- `NODE_ENV` - Set to `test`

### Viewing Results

1. Go to your GitHub repository
2. Click "Actions" tab
3. Select "Backend Tests" workflow
4. View test results and logs

---

## Xcode Cloud

### Setup Instructions

1. **Enable Xcode Cloud** (in Xcode or App Store Connect):
   - Open Xcode
   - Go to Product → Xcode Cloud → Create Workflow
   - Or visit App Store Connect → Apps → Your App → Xcode Cloud

2. **Create Test Workflow**:
   - Workflow Name: "PR Validation" or "Main Branch Tests"
   - Branch: `cursor/cokeep-maintenance-app-72f3`
   - Actions: Test
   - Platform: iOS Simulator
   - Device: iPhone 15 (iOS 17+)

3. **Configure Test Plan** (in Xcode):
   - Select your app target
   - Go to Product → Scheme → Edit Scheme
   - Under Test tab, create or edit test plan
   - Add `CoKeepTests` target
   - Save test plan as "CoKeep"

### Post-Clone Script

Location: `ios/ci_scripts/ci_post_clone.sh`

This script runs after Xcode Cloud clones your repo. You can use it to:
- Set environment variables
- Download test fixtures
- Generate mock data
- Configure test environment

### Viewing Results

1. Open Xcode
2. Go to Report Navigator (`Cmd+9`)
3. Select "Cloud" section
4. View test results, logs, and artifacts

---

## Heroku CI

Heroku **does support CI** through Heroku Pipelines! Here's how to set it up:

### Setup Instructions

1. **Create a Pipeline** (if not already):
   ```bash
   heroku pipelines:create cokeep --app your-app-name
   ```

2. **Enable Heroku CI**:
   - Go to https://dashboard.heroku.com
   - Select your pipeline
   - Click "Tests" tab
   - Click "Enable Heroku CI"

3. **Create `app.json`** in your repo root:

```json
{
  "name": "CoKeep",
  "description": "Co-owned property maintenance tracker",
  "repository": "https://github.com/lindea/cokeep",
  "env": {
    "NODE_ENV": {
      "value": "test"
    },
    "JWT_SECRET": {
      "value": "test-secret-for-heroku-ci"
    }
  },
  "addons": [
    {
      "plan": "heroku-postgresql",
      "options": {
        "version": "16"
      }
    }
  ],
  "buildpacks": [
    {
      "url": "heroku/nodejs"
    }
  ],
  "environments": {
    "test": {
      "scripts": {
        "test": "cd backend && npm test"
      },
      "formation": {
        "test": {
          "quantity": 1,
          "size": "standard-1x"
        }
      }
    }
  }
}
```

### How It Works

1. **Automatic Runs**: CI runs automatically on every push and PR
2. **Test Database**: Heroku provisions a fresh PostgreSQL database
3. **Build & Test**: Runs your npm test script
4. **Results**: View in pipeline dashboard or get notifications

### Viewing Results

1. Visit https://dashboard.heroku.com
2. Go to your pipeline
3. Click "Tests" tab
4. View test runs, logs, and history

### Test Environment

Heroku CI provides:
- Fresh database for each test run
- All environment variables from `app.json`
- Isolated test environment
- Automatic cleanup after tests

---

## Best Practices

### Backend Tests

- ✅ Test validation logic
- ✅ Test edge cases
- ✅ Mock external services (S3, email, push notifications)
- ✅ Test database operations with test database
- ✅ Keep tests fast and independent

### iOS Tests

- ✅ Test view models and business logic
- ✅ Test data formatting functions
- ✅ Test model validation
- ✅ Mock network calls (APIClient)
- ✅ Use XCTest expectations for async code

### CI/CD

- ✅ Run tests on every PR
- ✅ Require passing tests before merge
- ✅ Test against multiple Node.js versions (backend)
- ✅ Test on multiple iOS versions (when applicable)
- ✅ Keep CI builds fast (< 10 minutes)

---

## Troubleshooting

### Backend Tests Failing

```bash
# Check Node.js version
node --version  # Should be 20.x or higher

# Clean install
rm -rf node_modules package-lock.json
npm install

# Check database connection
DATABASE_URL=postgresql://... npx prisma migrate status
```

### iOS Tests Failing

1. Clean build folder: `Cmd+Shift+K` in Xcode
2. Reset simulators: `xcrun simctl erase all`
3. Delete derived data: `rm -rf ~/Library/Developer/Xcode/DerivedData`
4. Verify test target is included in scheme

### CI Failing

- Check CI logs for specific errors
- Verify all secrets/env variables are set
- Test locally first
- Check for platform-specific issues

---

## Adding More Tests

As you add features, add corresponding tests:

1. **Backend API endpoints** → Add integration tests
2. **Business logic functions** → Add unit tests
3. **iOS views** → Add snapshot or UI tests (future)
4. **Data models** → Add validation tests

Run tests before committing:
```bash
# Backend
cd backend && npm test

# iOS
# In Xcode: Cmd+U
```

---

## CI Status Badges

Add to your README.md:

```markdown
![Backend Tests](https://github.com/lindea/cokeep/workflows/Backend%20Tests/badge.svg)
```

---

For questions or issues, check the logs in:
- GitHub Actions → Actions tab
- Xcode Cloud → Report Navigator in Xcode
- Heroku CI → Pipeline Tests tab
