import XCTest
@testable import CoKeep

/// Unit tests for todo-related functionality
final class TodoViewModelTests: XCTestCase {
    
    // MARK: - Date Formatting Tests
    
    func testFormatDateParsesISOString() {
        let isoDate = "2026-07-31T12:00:00Z"
        let formatted = formatDate(isoDate)
        
        XCTAssertFalse(formatted.isEmpty, "Formatted date should not be empty")
        XCTAssertNotEqual(formatted, isoDate, "Should format the date, not return raw ISO")
    }
    
    func testFormatDateHandlesInvalidInput() {
        let invalidDate = "not-a-date"
        let formatted = formatDate(invalidDate)
        
        XCTAssertEqual(formatted, invalidDate, "Should return input for invalid dates")
    }
    
    // MARK: - Duration Formatting Tests
    
    func testFormatDurationMinutesOnly() {
        XCTAssertEqual(formatDuration(0), "0m")
        XCTAssertEqual(formatDuration(30), "30m")
        XCTAssertEqual(formatDuration(59), "59m")
    }
    
    func testFormatDurationHoursAndMinutes() {
        XCTAssertEqual(formatDuration(60), "1h 0m")
        XCTAssertEqual(formatDuration(90), "1h 30m")
        XCTAssertEqual(formatDuration(125), "2h 5m")
    }
    
    func testFormatDurationMultipleHours() {
        XCTAssertEqual(formatDuration(180), "3h 0m")
        XCTAssertEqual(formatDuration(245), "4h 5m")
    }
    
    // MARK: - Date Range Formatting Tests
    
    func testFormatLogDateRangeSameDay() {
        let start = "2026-07-31T10:00:00Z"
        let end = "2026-07-31T12:30:00Z"
        let formatted = formatLogDateRange(startedAt: start, endedAt: end)
        
        XCTAssertTrue(formatted.contains("•"), "Same-day format should use bullet separator")
        XCTAssertTrue(formatted.contains("-"), "Should contain time range separator")
    }
    
    func testFormatLogDateRangeDifferentDays() {
        let start = "2026-07-31T22:00:00Z"
        let end = "2026-08-01T02:00:00Z"
        let formatted = formatLogDateRange(startedAt: start, endedAt: end)
        
        XCTAssertTrue(formatted.contains("-"), "Should contain range separator")
        // Different day format should not use bullet
        XCTAssertFalse(formatted.contains("•"), "Different-day format should not use bullet")
    }
    
    func testFormatLogDateRangeHandlesInvalidDates() {
        let start = "invalid-start"
        let end = "invalid-end"
        let formatted = formatLogDateRange(startedAt: start, endedAt: end)
        
        XCTAssertTrue(formatted.contains(start), "Should include start date")
        XCTAssertTrue(formatted.contains(end), "Should include end date")
    }
    
    // MARK: - ISO Date Parsing Tests
    
    func testParseISODateWithFractionalSeconds() {
        let isoDate = "2026-07-31T12:00:00.123Z"
        let parsed = parseISODate(isoDate)
        
        XCTAssertNotNil(parsed, "Should parse date with fractional seconds")
    }
    
    func testParseISODateWithoutFractionalSeconds() {
        let isoDate = "2026-07-31T12:00:00Z"
        let parsed = parseISODate(isoDate)
        
        XCTAssertNotNil(parsed, "Should parse date without fractional seconds")
    }
    
    func testParseISODateReturnsNilForInvalid() {
        let invalidDate = "not-a-date"
        let parsed = parseISODate(invalidDate)
        
        XCTAssertNil(parsed, "Should return nil for invalid date string")
    }
}

/// Tests for model validation and business logic
final class TodoItemTests: XCTestCase {
    
    func testTodoItemPhotoModel() {
        let photo = TodoItemPhoto(
            id: "test-id",
            imageUrl: "https://example.com/photo.jpg",
            caption: "Test caption",
            sortOrder: 0
        )
        
        XCTAssertEqual(photo.id, "test-id")
        XCTAssertEqual(photo.imageUrl, "https://example.com/photo.jpg")
        XCTAssertEqual(photo.caption, "Test caption")
        XCTAssertEqual(photo.sortOrder, 0)
    }
    
    func testTodoItemPhotoOptionalCaption() {
        let photo = TodoItemPhoto(
            id: "test-id",
            imageUrl: "https://example.com/photo.jpg",
            caption: nil,
            sortOrder: 0
        )
        
        XCTAssertNil(photo.caption)
    }
}
