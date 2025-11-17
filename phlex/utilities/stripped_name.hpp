#ifndef PHLEX_UTILITIES_STRIPPED_NAME_HPP
#define PHLEX_UTILITIES_STRIPPED_NAME_HPP

#include "phlex_utilities_export.hpp"
#include <string>

namespace phlex::experimental {
  namespace detail {

    phlex_utilities_EXPORT std::string stripped_name(std::string full_name);
  }
}

#endif // PHLEX_UTILITIES_STRIPPED_NAME_HPP
