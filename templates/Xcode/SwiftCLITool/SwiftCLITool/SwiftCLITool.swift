/*****************************************************************************************
 * SwiftCLITool.swift
 *
 *
 *
 * Author   :  Gary Ash <gary.ash@icloud.com>
 * Created  :  20-Feb-2026  5:21pm
 * Modified :
 *
 * Copyright © 2026 By CompanyName All rights reserved.
 ****************************************************************************************/

import ArgumentParser
import SwiftCLIToolCore

@main
struct SwiftCLITool: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "SwiftCLITool",
		abstract: "A Swift 6 command line tool."
	)

	@Argument(help: "Name to greet.")
	var name: String = "world"

	mutating func run() async throws {
		print(greet(name: name))
	}
}
