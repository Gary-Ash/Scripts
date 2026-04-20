/*****************************************************************************************
 * Greeter.hpp
 *
 *
 *
 * Author   :  Gary Ash <gary.ash@icloud.com>
 * Created  :  20-Feb-2026  5:21pm
 * Modified :
 *
 * Copyright © 2026 By CompanyName All rights reserved.
 ****************************************************************************************/

#pragma once

#include <string>
#include <string_view>

inline std::string greet(std::string_view name) {
	std::string out = "Hello, ";
	out.append(name);
	out.push_back('!');
	return out;
}
