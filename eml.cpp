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
#include <span>
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

enum class word_class { unknown, number, built_in, macro };

struct options_type {
    bool expand{false};
};

options_type parse_options(std::span<const std::string_view> args)
{
    options_type options;
    for (auto& arg: args) {
        if ("--expand" == arg) {
            options.expand = true;
        }
    }
    //TODO: Catch unknown options
    return options;
}

[[noreturn]] void throw_string(std::string message)
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

std::pair<word_class, number_type> classify(const std::string& word)
{
    if (auto maybe_number{parse_number(word)}; maybe_number) {
        return std::make_pair(word_class::number, *maybe_number);
    }
    if (the_built_ins.contains(word)) return std::make_pair(word_class::built_in, 0);
    if (the_macros.contains(word)) return std::make_pair(word_class::macro, 0);
    return std::make_pair(word_class::unknown, 0);
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
    //TODO: Use ranges to split words instead?
    std::istringstream stream{body};
    std::string token;
    while (stream >> token) {
        auto [klass, _] = classify(token);
        if (word_class::unknown == klass) return token;
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
        auto [klass, _] = classify(name);
        switch (klass) {
            case word_class::number:
                throw_string(std::format("{}: A macro name cannot be a number", name));
                break;
            case word_class::built_in:
                throw_string(std::format("{} is a built-in and cannot be a macro", name));
                break;
            case word_class::macro:
                throw_string(std::format("Duplicate macros are not allowed ({})", name));
                break;
            case word_class::unknown:
                break;
        }
        auto value{line.substr(colon + 1)};
        if (auto undefined{find_undefined_macro(value)}; undefined) {
            throw_string(std::format("The {} macro tries to call the undefined macro {}", name, *undefined));
        }
        the_macros[name] = value;
    }
}

// Calls on_word for each number and built-in found in the stream replacing macros with their expansion.
void expand(std::istream& in, auto&& on_word)
{
    std::string word;
    while (in >> word) {
        auto [klass, _] = classify(word);
        switch (klass) {
            case word_class::number:
                [[fallthrough]];
            case word_class::built_in:
                on_word(word);
                break;
            case word_class::macro:
                {
                    std::istringstream body{the_macros.at(word)};
                    expand(body, on_word);
                }
                break;
            case word_class::unknown:
                throw_string(std::format("Unknown macro: {}", word));
                break;
        }
    }
}

void evaluate(const std::string& word, number_stack& the_stack)
{
    // We could have expand pass the parsed number in the number case.
    // For now, we'll leave it like this. Eventually this function should only see 1.
    auto [klass, number] = classify(word);
    switch (klass) {
        case word_class::number:
            //TODO: Only accept 1?
            the_stack.push(number);
            break;
        case word_class::built_in:
            the_built_ins.at(word)(the_stack);
            break;
        case word_class::macro:
            [[fallthrough]];
        case word_class::unknown:
            throw std::logic_error(std::format("Evaluate was given \"{}\"", word));
            break;
    }
}

} // end of anonymous namespace

int main(int argc, char** argv)
{
    try {
        auto args{std::vector<std::string_view>(argv + 1, argv + argc)};
        auto options{parse_options(args)};
        initialize_built_ins();
        read_library();
        number_stack the_stack;

        if (options.expand) {
            bool first{true};
            expand(std::cin, [&first](const std::string& word)
                    {
                        if (not std::exchange(first, false)) std::cout << ' ';
                        std::cout << word;
                    });
            std::cout << '\n';
        } else {
            expand(std::cin, [&the_stack](const std::string& word){ evaluate(word, the_stack); });
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
        }
        return EXIT_SUCCESS;
    } catch (std::exception& e) {
        std::cerr << "EXCEPTION: " << e.what() << '\n';
        return EXIT_FAILURE;
    } catch (...) {
        std::cerr << "EXCEPTION\n";
        return EXIT_FAILURE;
    }
}

