#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <format>
#include <fstream>
#include <functional>
#include <iostream>
#include <istream>
#include <optional>
#include <ostream>
#include <sstream>
#include <stack>
#include <stdexcept>
#include <string>
#include <string_view>
#include <unordered_map>

// Build with -DEML_USE_BOOST to use Boost.Multiprecision's cpp_complex_50
// (50 decimal digits) instead of std::complex<double>.
#ifdef EML_USE_BOOST
#include <boost/multiprecision/cpp_complex.hpp>
using number_type = boost::multiprecision::cpp_complex_50;
#else
#include <complex>
using number_type = std::complex<double>;
#endif
using number_stack = std::stack<number_type>;

namespace {
std::unordered_map<std::string, std::string> the_macros;

std::unordered_map<std::string, std::function<void(number_stack&)>> the_built_ins;

void throw_string(std::string message)
{
    throw std::runtime_error{message};
}

bool is_whitespace(unsigned char c) { return std::isspace(c); }

bool is_digit(unsigned char c) { return std::isdigit(c); }

// Prints n as (real,imag). std::complex already prints that way, but Boost's
// cpp_complex leaves out the parentheses and imaginary part when it's zero.
void print_number(std::ostream& out, const number_type& n)
{
    out << '(' << n.real() << ',' << n.imag() << ')';
}

//NOTE: We intentionally copy the_stack instead of taking it by reference.
void print_stack(std::ostream& out, number_stack the_stack)
{
    while (not the_stack.empty()) {
        print_number(out, the_stack.top());
        out << '\n';
        the_stack.pop();
    }
}

bool is_empty_string(std::string_view sv)
{
    return std::ranges::all_of(sv, is_whitespace);
}

void trim(std::string& s)
{
    // For our purposes, we can just strip all whitespace.
    std::erase_if(s, is_whitespace);
}

// We don't get a string_view ctor for istringstream until C++26
// We don't get ispanstream until C++23.
std::optional<number_type> parse_number(const std::string& s)
{
    // A number must contain a digit. Without this check, Boost's cpp_complex
    // reads "-" as 0, which would hide the - macro.
    if (std::ranges::none_of(s, is_digit)) return std::nullopt;
    std::istringstream in(s);
    number_type n;
    try {
        if (in >> n and (in >> std::ws).eof()) return n;
        // The (in >> std::ws).eof() makes sure there's no characters following the number.
    } catch (const std::runtime_error&) {
        // Boost's cpp_complex throws on input like "1abc" instead of failing the stream.
    }
    return std::nullopt;
}

auto pop(auto& the_stack)
{
    if (the_stack.empty()) throw_string("Tried to pop an empty stack.");
    auto n{the_stack.top()};
    the_stack.pop();
    return n;
}

void initialize_built_ins()
{
    the_built_ins["eml"] =
        [](number_stack& the_stack)
        {
            auto y{pop(the_stack)};
            auto x{pop(the_stack)};
            // Unqualified, so argument-dependent lookup finds the right
            // exp and log for either number type.
            the_stack.push(exp(x) - log(y));
        };

    the_built_ins["swap"] =
        [](number_stack& the_stack)
        {
            auto y{pop(the_stack)};
            auto x{pop(the_stack)};
            the_stack.push(y);
            the_stack.push(x);
        };
    the_built_ins["dup"] =
        [](number_stack& the_stack)
        {
            auto x{pop(the_stack)};
            the_stack.push(x);
            the_stack.push(x);
        };
}

std::optional<std::string> find_undefined_macro(const std::string& body)
{
    std::istringstream stream{body};
    std::string token;
    while (stream >> token) {
        if (parse_number(token)) continue;
        if (the_built_ins.contains(token)) continue;
        if (not the_macros.contains(token)) {
            return token;
        }
    }
    return std::nullopt;
}

void read_library()
{
    std::ifstream file("library.eml");
    if (not file) throw_string("Failed to open library.eml");
    std::string line;
    while (std::getline(file, line)) {
        if (is_empty_string(line)) continue;
        if ('#' == line.at(0)) continue;
        auto colon{line.find(':')};
        if (line.npos == colon) throw_string("No colon found in macro");
        auto name{line.substr(0, colon)};
        trim(name);
        if (name.empty()) {
            throw_string("A macro name cannot be empty");
        }
        if (parse_number(name)) {
            throw_string(std::format("{}: A macro name cannot be a number", name));
        }
        if (the_built_ins.contains(name)) {
            throw_string(std::format("{} is a built-in and cannot be a macro", name));
        }
        if (the_macros.contains(name)) {
            throw_string(std::format("Duplicate macros are not allowed ({})", name));
        }
        auto value{line.substr(colon + 1)};
        if (auto undefined{find_undefined_macro(value)}; undefined) {
            throw_string(std::format("The {} macro tries to call the undefined macro {}", name, *undefined));
        }
        the_macros[name] = value;
    }
}

void evaluate(std::istream& in, number_stack& the_stack)
{
    std::string token;
    while (in >> token) {
        if (auto maybe_number{parse_number(token)}; maybe_number) {
            //TODO: Only accept 1?
            the_stack.push(*maybe_number);
            continue;
        }
        if (auto built_in_iter{the_built_ins.find(token)}; the_built_ins.end() != built_in_iter) {
            (built_in_iter->second)(the_stack);
            continue;
        }
        if (auto macro_iter{the_macros.find(token)}; the_macros.end() != macro_iter) {
            std::istringstream macro_stream{macro_iter->second};
            evaluate(macro_stream, the_stack);
            continue;
        }
        throw_string(std::format("Unknown macro: {}", token));
    }
}
} // end of anonymous namespace

int main()
{
    try {
        initialize_built_ins();
        read_library();
        number_stack the_stack;
        evaluate(std::cin, the_stack);
        if (1 != the_stack.size()) {
            if (the_stack.empty()) {
                std::cerr << "ERROR: Empty stack\n";
            } else {
                std::cerr << "ERROR: Too many values on the stack\n";
                print_stack(std::cerr, the_stack);
            }
            return EXIT_FAILURE;
        }
        print_number(std::cout, the_stack.top());
        std::cout << '\n';
        return EXIT_SUCCESS;
    } catch (std::exception& e) {
        std::cerr << "EXCEPTION: " << e.what() << '\n';
        return EXIT_FAILURE;
    } catch (...) {
        std::cerr << "EXCEPTION\n";
        return EXIT_FAILURE;
    }
}

