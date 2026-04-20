/*****************************************************************************************
 * main.cpp
 *
 *
 *
 * Author   :  Gary Ash <gary.ash@icloud.com>
 * Created  :  20-Feb-2026  5:21pm
 * Modified :
 *
 * Copyright © 2026 By CompanyName All rights reserved.
 ****************************************************************************************/

#include <iostream>
#include <string>
#include <string_view>
#include <vector>

#include "Greeter.hpp"

int main(int argc, const char *argv[]) {
	const std::vector<std::string_view> args(argv + 1, argv + argc);
	const std::string_view name = args.empty() ? "world" : args.front();
	std::cout << greet(name) << '\n';
	return 0;
}
