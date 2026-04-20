/*****************************************************************************************
 * SwiftCLIToolTests.swift
 *
 *
 *
 * Author   :  Gary Ash <gary.ash@icloud.com>
 * Created  :  20-Feb-2026  5:21pm
 * Modified :
 *
 * Copyright © 2026 By CompanyName All rights reserved.
 ****************************************************************************************/

@testable import SwiftCLIToolCore
import Testing

struct SwiftCLIToolTests {

	@Test func greetReturnsHelloWithName() async throws {
		#expect(greet(name: "world") == "Hello, world!")
		#expect(greet(name: "Gary") == "Hello, Gary!")
	}

}
