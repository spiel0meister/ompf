package ompf

import "base:intrinsics"
import "core:fmt"
import "core:reflect"
import "core:strings"
import "core:text/match"
import "core:os"
import "core:testing"

Flag :: struct {
    name: string,
    type: typeid,
    offset: uintptr,

    no_subcommand: bool,
    usage: Maybe(string),
    // TODO: subcommand: Maybe(string)
}

Subcommand_Value :: struct {
    name: string,
    value: i64,
}

flag_delete :: proc(flag: ^Flag) {
    delete(flag.name)
}

maybe_trim_quotes :: proc(str: string) -> (rest: string, ok: bool) {
    ok = strings.has_prefix(str, "\"") && strings.has_suffix(str, "\"")
    if ok {
        rest = strings.trim_prefix(str, "\"")
        rest = strings.trim_suffix(rest, "\"")
    }
    return
}

print_usage :: proc(program: string, subcommands: []Subcommand_Value, flags: []Flag, h := os.stderr) {
    fmt.fprintfln(h, "Usage: {} [GLOBAL FLAGS] <SUBCOMMAND> [SUBCOMMAND FLAGS]", program)
    fmt.fprintfln(h, "Subcommands:")
    for subcommand in subcommands {
        fmt.fprintfln(h, "    {}", subcommand.name)
    }
    fmt.fprintfln(h, "Global flags:")
    for flag in flags {
        if len(flag.name) == 1 {
            fmt.fprintf(h, "    -{}", flag.name)
        } else {
            fmt.fprintf(h, "    --{}", flag.name)
        }

        if flag.usage != nil {
            fmt.fprintf(h, " | {}", flag.usage)
        }

        fmt.fprintln(h)
    }
}

tag_next_property :: proc(view: string) -> (prop: string, rest: string, ok: bool) {
    view := strings.trim_left_space(view)

    i := 0
    in_string := false
    for ; i < len(view); i += 1 {
        if match.is_space(auto_cast view[i]) && !in_string {
            break
        }

        if view[i] == '"' {
            in_string = !in_string
        }
    }

    ok = i > 0
    if ok {
        prop = view[:i]
        rest = view[i:]
    }
    return
}

type_to_flags :: proc($S: typeid, allocator := context.allocator) -> (flags: [dynamic]Flag, subcommand_offset: uintptr, subcommands: [dynamic]Subcommand_Value) where intrinsics.type_is_struct(S) {
    fields := reflect.struct_fields_zipped(S)

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)

    for field in fields {
        if reflect.is_struct(field.type) {
            fmt.panicf("TODO: flag cannot be a struct")
        } else if reflect.is_union(field.type) {
            fmt.panicf("TODO: flag cannot be a struct")
        } else if reflect.is_pointer(field.type) {
            fmt.panicf("TODO: flag cannot be a pointer")
        }

        if field.name == "subcommand" {
            subcommand_offset = field.offset

            enum_fields := reflect.enum_fields_zipped(field.type.id)
            for enum_field in enum_fields {
                for c in enum_field.name {
                    if c == '_' {
                        strings.write_rune(&builder, '-')
                    } else if c >= 'A' && c <= 'Z' {
                        strings.write_rune(&builder, c + 32)
                    } else {
                        strings.write_rune(&builder, c)
                    }
                }

                subcommands_value := Subcommand_Value{
                    name = strings.clone(strings.to_string(builder), allocator),
                    value = auto_cast enum_field.value,
                }
                append(&subcommands, subcommands_value)

                strings.builder_reset(&builder)
            }
            continue
        } else {
            name := field.name
            if name == "help" || name == "h" {
                fmt.panicf(`Using reserved flags "help" and "h"`)
            }

            for c in name {
                if c == '_' {
                    strings.write_rune(&builder, '-')
                } else {
                    strings.write_rune(&builder, c)
                }
            }

            flag := Flag{
                name = strings.clone(strings.to_string(builder), allocator),
                type = field.type.id,
                offset = field.offset,
            }

            tag := cast(string)field.tag
            if len(tag) > 0 {
                tag_view := tag
                props := strings.split(tag, " ", context.temp_allocator)
                for prop, rest in tag_next_property(tag_view) {
                    tag_view = rest

                    if prop == "no_subcommand" {
                        flag.no_subcommand = true
                        continue
                    }

                    if strings.has_prefix(prop, "alias:") {
                        aliases_should_be_in_qoutes := strings.trim_prefix(prop, "alias:")

                        if aliases_commas, ok := maybe_trim_quotes(aliases_should_be_in_qoutes); ok {
                            aliases_commas := strings.trim_suffix(strings.trim_prefix(aliases_should_be_in_qoutes, `"`), `"`)
                            aliases := strings.split(aliases_commas, ",")

                            for alias in aliases {
                                alias := strings.trim_space(alias)
                                // TODO: check if alias has spaces

                                // TODO: instead of adding a separate flag for the alias,
                                //       maybe have the flag have a list of aliases
                                flag_alias := flag
                                flag_alias.name = strings.clone(alias, allocator)
                                append(&flags, flag_alias)
                            }
                        } else {
                            fmt.panicf("Expected aliases to be in double quotes")
                        }

                        continue
                    }

                    if strings.has_prefix(prop, "usage:") {
                        usage_in_quotes := strings.trim_prefix(prop, "usage:")

                        if usage, ok := maybe_trim_quotes(usage_in_quotes); ok {
                            flag.usage = usage
                        } else {
                            fmt.panicf("Expected usage to be in qoutes")
                        }

                        continue
                    }

                    fmt.panicf("Unhandled prop {}", prop)
                }
            }

            append(&flags, flag)

            strings.builder_reset(&builder)
        }
    }

    return
}

set_flag_value :: proc(out, offset: uintptr, type: typeid, value_as_string: string) {
    switch type {
    case string:
        (cast(^string)(cast(uintptr)out + offset))^ = value_as_string
    case:
        fmt.panicf("TODO: Unhandled flag type {}", type)
    }
}

// TODO: parse struct field tags
parse_args :: proc(out: ^$S) -> (program: string, ok := true) where intrinsics.type_is_struct(S) {
    flags, subcommand_offset, subcommands := type_to_flags(S)
    defer delete(flags)
    defer delete(subcommands)
    defer for &flag in flags {
        flag_delete(&flag)
    }

    args := os.args

    program = args[0]
    pos := 0

    subcommand_required := true
    subcommand: Maybe(string)

    outer_loop:for i := 1; i < len(args); i += 1 {
        arg := args[i]
        if strings.has_prefix(arg, "--") {
            arg_without_prefix := strings.trim_prefix(arg, "--")

            if arg_without_prefix == "help" {
                print_usage(program, subcommands[:], flags[:], os.stdout)
                os.exit(0)
            }

            for flag in flags {
                if flag.name == arg_without_prefix {
                    subcommand_required &= !flag.no_subcommand

                    if flag.type == bool {
                        (cast(^bool)(cast(uintptr)out + flag.offset))^ = true
                        continue outer_loop
                    }

                    i += 1
                    if i >= len(args) {
                        fmt.eprintfln("Unexpected end of arguments")
                        print_usage(program, subcommands[:], flags[:])
                        ok = false
                        return
                    }

                    flag_string_value := args[i]
                    set_flag_value(cast(uintptr)out, flag.offset, flag.type, flag_string_value)

                    continue outer_loop
                }
            }

            fmt.eprintfln("Unknown flag {}", arg)
            print_usage(program, subcommands[:], flags[:])
            ok = false
            return
        } else if strings.has_prefix(arg, "-") {
            arg_without_prefix := strings.trim_prefix(arg, "-")
            if len(arg_without_prefix) != 1 {
                fmt.eprintln("Flags that begin with one `-` must have only one letter")
                print_usage(program, subcommands[:], flags[:])
                ok = false
                return
            }

            if arg_without_prefix == "h" {
                print_usage(program, subcommands[:], flags[:], os.stdout)
                os.exit(0)
            }

            for flag in flags {
                if len(flag.name) != 1 {
                    continue
                } else if arg_without_prefix == flag.name {
                    subcommand_required &= !flag.no_subcommand

                    if flag.type == bool {
                        (cast(^bool)(cast(uintptr)out + flag.offset))^ = true
                        continue outer_loop
                    }

                    i += 1
                    if i >= len(args) {
                        fmt.eprintfln("Unexpected end of arguments")
                        print_usage(program, subcommands[:], flags[:])
                        ok = false
                        return
                    }

                    flag_string_value := args[i]
                    set_flag_value(cast(uintptr)out, flag.offset, flag.type, flag_string_value)

                    continue outer_loop
                }
            }

            fmt.eprintfln("Unkown flag {}", arg)
            print_usage(program, subcommands[:], flags[:])
            ok = false
            return
        }

        if pos == 0 {
            found := false
            for subcommand_ in subcommands {
                if arg == subcommand_.name {
                    subcommand = subcommand_.name
                    (cast(^i64)(cast(uintptr)out + subcommand_offset))^ = subcommand_.value
                    found = true
                    break
                }
            }

            if !found {
                fmt.eprintfln("Expected subcommand")
                print_usage(program, subcommands[:], flags[:])
                ok = false
                return
            }
        } else {
            fmt.panicf("TODO: positional arguments")
        }
    }

    if subcommand_required && subcommand == nil {
        fmt.eprintfln("Expected subcommand")
        print_usage(program, subcommands[:], flags[:])
        ok = false
        return
    }

    return
}

@(test)
test_tag_next_property :: proc(t: ^testing.T) {
    TAG :: `no_subcommand usage:"Usage" alias:"alias"`

    expected_props := []string{
        "no_subcommand",
        `usage:"Usage"`,
        `alias:"alias"`,
    }
    i := 0

    tag_view := TAG
    for prop, rest in tag_next_property(tag_view) {
        tag_view = rest
        testing.expectf(t, prop == expected_props[i], "Prop: {}; expected: {}", prop, expected_props[i])
        i += 1
    }
}
