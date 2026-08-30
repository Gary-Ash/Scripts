/*****************************************************************************************
 * SwiftCLITool.swift
 *
 *
 *
 * Author   :  Gary Ash <gary.ash@icloud.com>
 * Created  :   1-Sep-2026  4:42pm
 * Modified :
 *
 * Copyright © 2026 By Gary Ash All rights reserved.
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
