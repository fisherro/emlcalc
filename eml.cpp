#include <algorithm>
#include <array>
#include <cctype>
#include <cstdlib>
#include <format>
#include <fstream>
#include <functional>
#include <iostream>
#include <istream>
#include <limits>
#include <optional>
#include <ostream>
#include <ranges>
#include <span>
#include <sstream>
#include <stack>
#include <stdexcept>
#include <string>
#include <string_view>
#include <unordered_map>
#include <utility>
#include <vector>

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

constexpr int EXIT_USAGE{2};

struct options_type {
    std::vector<std::string_view> files;
    std::string library;
    bool strict{false};
    bool expand{false};
    bool clean{false};
};

struct usage_error: std::runtime_error {
    using std::runtime_error::runtime_error;
};

const std::string help_text =
R"(Usage: eml [--strict] [--expand] [--library <file>] [<file> ...]
Reads an RPN expression from standard input or given files.
  -s, --strict  Only accepts 1, eml, and stack operations
  -e, --expand  Transforms expression for use with --strict
  -c, --clean   Round small values to zero
  -l, --library File path to the macro library
  -h, --help    Prints this text
)";

constexpr auto& at(const auto& container, size_t position)
{
    if (position >= std::size(container)) {
        throw std::out_of_range{std::format("Index out of range: {} >= {}", position, std::size(container))};
    }
    return container[position];
}

options_type parse_options(std::span<const std::string_view> args)
{
    options_type options;
    for (int i{0}; i < std::ssize(args); ++i) {
        std::string_view arg = at(args, i);
        auto match = [arg](char s, std::string_view l)
        {
            if (('\0' != s) and ((std::string("-") + s) == arg)) return true;
            if ((not l.empty()) and ((std::string("--").append(l)) == arg)) return true;
            return false;
        };
        if (match('s', "strict")) {
            options.strict = true;
        } else if (match('e', "expand")) {
            options.expand = true;
        } else if (match('l', "library")) {
            ++i;
            if (i >= std::ssize(args)) {
                throw usage_error{"--library must be followed by a file path"};
            } else {
                options.library = at(args, i);
            }
        } else if (match('h', "help")) {
            std::cout << help_text;
            std::exit(EXIT_SUCCESS);
        } else if (match('c', "clean")) {
            options.clean = true;
        } else if (arg.starts_with("-")) {
            throw usage_error{std::format("Unrecognized option: {}", arg)};
        } else {
            options.files.push_back(arg);
        }
    }
    if (options.strict and options.expand) {
        throw usage_error{"The --strict and --expand options are mutually exclusive."};
    }
    return options;
}

[[noreturn]] void throw_string(std::string message)
{
    throw std::runtime_error{message};
}

bool is_whitespace(unsigned char c) { return std::isspace(c); }

bool is_digit(unsigned char c) { return std::isdigit(c); }

void print_number(std::ostream& out, number_type n, bool clean)
{
    if (clean) {
        using value_type = number_type::value_type;
        using limits = std::numeric_limits<value_type>;
        static const value_type tolerance{10'000 * limits::epsilon()};
        static const value_type floor{1'000 * limits::epsilon()};
        value_type limit{tolerance * abs(n)};
        if (limit < floor) limit = floor;
        if (abs(n.real()) < limit) n.real(0);
        if (abs(n.imag()) < limit) n.imag(0);
    }
    if (0 == n.imag()) {
        out << n.real();
    } else {
        out << '(' << n.real() << ',' << n.imag() << ')';
    }
}

//NOTE: We intentionally copy the_stack instead of taking it by reference.
void print_stack(std::ostream& out, number_stack the_stack, bool clean)
{
    while (not the_stack.empty()) {
        print_number(out, the_stack.top(), clean);
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

std::optional<number_type> parse_number(std::string_view sv)
{
    // A number must contain a digit. Without this check, Boost's cpp_complex
    // reads "-" as 0, which would hide the - macro.
    if (std::ranges::none_of(sv, is_digit)) return std::nullopt;
    // We don't get a string_view ctor for istringstream until C++26
    // We don't get ispanstream until C++23.
    std::istringstream in{std::string(sv)};
    number_type n;
    try {
        if (in >> n and (in >> std::ws).eof()) return n;
        // The (in >> std::ws).eof() makes sure there's no characters following the number.
    } catch (const std::runtime_error&) {
        // Boost's cpp_complex throws on input like "1abc" instead of failing the stream.
    }
    return std::nullopt;
}

number_type parse_number_(std::string_view sv)
{
    return parse_number(sv).value();
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

template <size_t N>
auto multipop(auto& the_stack)
{
    if (the_stack.size() < N) throw_string("Tried to pop an empty stack.");
    using value_type = std::remove_cvref_t<decltype(the_stack)>::value_type;
    std::array<value_type, N> values;
    for (auto& value: values | std::views::reverse) {
        value = pop(the_stack);
    }
    return values;
}

template <typename Stack>
void multipush(Stack& the_stack, std::initializer_list<typename Stack::value_type> values)
{
    for (auto& value: values) {
        the_stack.push(value);
    }
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
            auto [x, y] = multipop<2>(the_stack);
            multipush(the_stack, {y, x});
        };

    the_built_ins["dup"] =
        [](number_stack& the_stack)
        {
            auto x{pop(the_stack)};
            multipush(the_stack, {x, x});
        };

    the_built_ins["over"] =
        [](number_stack& the_stack)
        {
            auto [x, y] = multipop<2>(the_stack);
            multipush(the_stack, {x, y, x});
        };

    the_built_ins["rot"] =
        [](number_stack& the_stack)
        {
            auto [x, y, z] = multipop<3>(the_stack);
            multipush(the_stack, {y, z, x});
        };

    the_built_ins["drop"] =
        [](number_stack& the_stack)
        {
            pop(the_stack);
        };

    the_built_ins["nip"] =
        [](number_stack& the_stack)
        {
            auto [_, y] = multipop<2>(the_stack);
            the_stack.push(y);
        };

    the_built_ins["tuck"] =
        [](number_stack& the_stack)
        {
            auto [x, y] = multipop<2>(the_stack);
            multipush(the_stack, {y, x, y});
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

void read_library(std::string path)
{
    if (path.empty()) path = "library.eml";
    std::ifstream file(path);
    if (not file) throw_string(std::format("Failed to open \"{}\"", path));
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

void check_library()
{
    static bool already_checked{false};
    if (already_checked) return;
    const std::vector<std::string> required{"ln", "-", "+", "*", "/", "^", "neg", "i"};
    std::vector<std::string> missing;
    for (auto& name: required) {
        if (not the_macros.contains(name)) missing.push_back(name);
    }
    if (not missing.empty()) {
        std::ostringstream message;
        message << "Library is missing these required macros: ";
        bool first{true};
        for (auto& name: missing) {
            if (not std::exchange(first, false)) message << ", ";
            message << name;
        }
        throw_string(message.str());
    }
    already_checked = true;
}

void expand_small_number(std::ostream& out, unsigned value)
{
    if (1 == value) {
        out << " 1";
    } else if (value > 0) {
        for (unsigned i{0}; i < value; ++i) out << " 1";
        for (unsigned i{1}; i < value; ++i) out << " +";
    }
}

void expand_real(std::ostream& out, std::string_view text)
{
    if ('+' == text.at(0)) text.remove_prefix(1);
    auto e{text.find_first_of("Ee")};
    std::string_view e_part;
    if (text.npos != e) {
        e_part = text.substr(e + 1);
        text = text.substr(0, e);
    }
    bool negative{false};
    if ('-' == text.at(0)) {
        negative = true;
        text.remove_prefix(1);
    }
    auto dot{text.find('.')};
    std::string_view fraction;
    if (text.npos != dot) {
        fraction = text.substr(dot + 1);
        text = text.substr(0, dot);
    }
    bool first{true};
    for (auto& digit: text) {
        if (first and ('0' == digit)) continue;
        if (not first) {
            expand_small_number(out, 10);
            out << " *";
        }
        if ('0' != digit) {
            expand_small_number(out, digit - '0');
            if (not first) out << " +";
        }
        first = false;
    }
    if (first) out << " 1 ln";
    if (not fraction.empty()) {
        expand_real(out, fraction);
        expand_small_number(out, 10);
        expand_real(out, std::to_string(fraction.size()));
        out << " ^ / +";
    }
    if (not e_part.empty()) {
        expand_small_number(out, 10);
        expand_real(out, e_part);
        out << " ^ *";
    }
    if (negative) out << " 1 neg *";
}

void expand_number(std::ostream& out, std::string_view text)
{
    const number_type zero{0};
    if ('(' == text.at(0)) {
        text.remove_prefix(1);
        text.remove_suffix(1);
        auto comma{text.find(',')};
        if (text.npos == comma) {
            expand_real(out, text);
            return;
        }
        auto real{text.substr(0, comma)};
        auto imag{text.substr(comma + 1)};
        auto r{parse_number_(real)};
        auto i{parse_number_(imag)};
        if ((zero == r) and (zero == i)) {
            out << " 1 ln";
        } else if (zero == i) {
            expand_real(out, real);
        } else if (zero == r) {
            expand_real(out, imag);
            out << " i *";
        } else if (abs(r) >= abs(i)) {
            out << " 1";
            expand_real(out, imag);
            expand_real(out, real);
            out << " / i * +";
            expand_real(out, real);
            out << " *";
        } else {
            out << " 1";
            expand_real(out, real);
            expand_real(out, imag);
            out << " / i * -";
            expand_real(out, imag);
            out << " i * *";
        }
        return;
    }
    expand_real(out, text);
}

// Calls on_word for each number and built-in found in the stream replacing macros with their expansion.
void expand(std::istream& in, auto&& on_word)
{
    std::string word;
    while (in >> word) {
        auto [klass, _] = classify(word);
        switch (klass) {
            case word_class::number:
#ifdef DONT_EXPAND_NUMBERS
                [[fallthrough]];
#else
                if ("1" == word) {
                    on_word(word);
                } else {
                    check_library();
                    std::ostringstream out;
                    expand_number(out, word);
                    std::istringstream other_in{out.str()};
                    expand(other_in, on_word);
                }
                break;
#endif
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

void evaluate(bool strict, const std::string& word, number_stack& the_stack)
{
    auto [klass, number] = classify(word);
    switch (klass) {
        case word_class::number:
#ifndef DONT_EXPAND_NUMBERS
            if ("1" != word) {
                throw_string(std::format("Numbers can only be 1. {} is not 1.", word));
            }
#endif
            the_stack.push(number);
            break;
        case word_class::built_in:
            the_built_ins.at(word)(the_stack);
            break;
        case word_class::macro:
            [[fallthrough]];
        case word_class::unknown:
            {
                std::ostringstream message;
                message << word << " not recognized\n";
                if (strict) {
                    message << "In strict mode, the only operations recognized are:\n";
                    bool first{true};
                    std::vector<std::string> built_ins;
                    std::ranges::copy(the_built_ins | std::views::keys, std::back_inserter(built_ins));
                    std::ranges::sort(built_ins);
                    for (auto& key: built_ins) {
                        if (not std::exchange(first, false)) message << ", ";
                        message << key;
                    }
                }
                throw std::runtime_error(message.str());
            }
            break;
    }
}

void go(const options_type& options, std::istream& in, std::ostream& out)
{ 
    number_stack the_stack;
    if (options.expand) {
        bool first{true};
        expand(in, [&first, &out](const std::string& word)
        {
            if (not std::exchange(first, false)) out << ' ';
            out << word;
        });
        out << '\n';
    } else if(options.strict) {
        std::string word;
        while (in >> word) {
            evaluate(options.strict, word, the_stack);
        }
    } else {
        expand(in, [&the_stack, &options](const std::string& word)
                { evaluate(options.strict, word, the_stack); });
    }

    if (not options.expand) {
        if (1 != the_stack.size()) {
            std::ostringstream message;
            if (the_stack.empty()) {
                message << "Empty stack";
            } else {
                message << "Too many values on the stack\n";
                print_stack(message, the_stack, options.clean);
            }
            throw_string(message.str());
        }
        print_number(out, the_stack.top(), options.clean);
        out << '\n';
    }
}

} // end of anonymous namespace

int main(int argc, char** argv)
{
    try {
        auto args{std::vector<std::string_view>(argv + 1, argv + argc)};
        auto options{parse_options(args)};
        initialize_built_ins();
        if (not options.strict) read_library(options.library);

        if (options.files.empty()) {
            go(options, std::cin, std::cout);
        } else {
            for (std::string_view file: options.files) {
                std::string s(file);
                std::ifstream in(s);
                if (not in) {
                    throw_string(std::format("File \"{}\" not found", file));
                }
                go(options, in, std::cout);
            }
        }

        return EXIT_SUCCESS;
    } catch (usage_error& e) {
        std::cerr << e.what() << '\n';
        std::cerr << help_text;
        return EXIT_USAGE;
    } catch (std::exception& e) {
        std::cerr << "EXCEPTION: " << e.what() << '\n';
        return EXIT_FAILURE;
    } catch (...) {
        std::cerr << "EXCEPTION\n";
        return EXIT_FAILURE;
    }
}

