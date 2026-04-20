/*****************************************************************************************
 * GreeterTests.mm
 *
 *
 *
 * Author   :  Gary Ash <gary.ash@icloud.com>
 * Created  :  20-Feb-2026  5:21pm
 * Modified :
 *
 * Copyright © 2026 By CompanyName All rights reserved.
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
