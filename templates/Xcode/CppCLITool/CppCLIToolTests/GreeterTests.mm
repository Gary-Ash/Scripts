/*****************************************************************************************
 * GreeterTests.mm
 *
 *
 *
 * Author   :  Gary Ash <gary.ash@icloud.com>
 * Created  :   1-Sep-2026  4:42pm
 * Modified :
 *
 * Copyright © 2026 By Gary Ash All rights reserved.
 ****************************************************************************************/

#import <XCTest/XCTest.h>

#include "Greeter.hpp"

@interface GreeterTests : XCTestCase
@end

@implementation GreeterTests

- (void)testGreetWithWorldReturnsHelloWorld {
	const std::string result = greet("world");

	XCTAssertEqual(result, std::string("Hello, world!"));
}

- (void)testGreetWithNameReturnsHelloName {
	const std::string result = greet("Gary");

	XCTAssertEqual(result, std::string("Hello, Gary!"));
}

@end
