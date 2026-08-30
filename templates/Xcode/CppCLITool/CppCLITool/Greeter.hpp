/*****************************************************************************************
 * Greeter.hpp
 *
 *
 *
 * Author   :  Gary Ash <gary.ash@icloud.com>
 * Created  :   1-Sep-2026  4:42pm
 * Modified :
 *
 * Copyright © 2026 By Gary Ash All rights reserved.
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
