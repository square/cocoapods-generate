#import <XCTest/XCTest.h>

@interface ForkableTests: XCTestCase
@end

@implementation ForkableTests

- (void)testFoo {
    XCTAssertTrue(YES);
}

@end