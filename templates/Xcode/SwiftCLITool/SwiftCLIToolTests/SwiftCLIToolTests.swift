/*****************************************************************************************
 * SwiftCLIToolTests.swift
 *
 *
 *
 * Author   :  Gary Ash <gary.ash@icloud.com>
 * Created  :   1-Sep-2026  4:42pm
 * Modified :
 *
 * Copyright © 2026 By Gary Ash All rights reserved.
 ****************************************************************************************/

@testable import SwiftCLIToolCore
import Testing

struct SwiftCLIToolTests {

	@Test func greetReturnsHelloWithName() async throws {
		#expect(greet(name: "world") == "Hello, world!")
		#expect(greet(name: "Gary") == "Hello, Gary!")
	}

}
