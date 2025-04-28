package ompf

import "base:intrinsics"
import "core:fmt"
import "core:reflect"
import "core:strings"
import "core:os"

Flag :: struct {
    name: string,
    type: typeid,
    offset: uintptr,
    // TODO: subcommand: Maybe(string)
}

flag_delete :: proc(flag: ^Flag) {
    delete(flag.name)
}

print_usage :: proc(program: string, subcommands: #soa[]reflect.Enum_Field, flags: []Flag, h := os.stderr) {
    fmt.fprintfln(h, "Usage: {} [GLOBAL FLAGS] <SUBCOMMAND> [SUBCOMMAND FLAGS]", program)
    fmt.fprintfln(h, "Subcommands:")
    for subcommand in subcommands {
        fmt.fprintfln(h, "    {}", subcommand.name)
    }
    fmt.fprintfln(h, "Global flags:")
    for flag in flags {
        fmt.fprintfln(h, "    --{}", flag.name)
    }
}

type_to_flags :: proc($S: typeid, allocator := context.allocator) -> (flags: [dynamic]Flag, subcommand_offset: uintptr, subcommands: #soa[]reflect.Enum_Field) where intrinsics.type_is_struct(S) {
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
            subcommands = reflect.enum_fields_zipped(field.type.id)
            continue
        }

        name := field.name
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
        append(&flags, flag)
    }
    return
}

parse_args :: proc(out: ^$S) -> (ok := true) where intrinsics.type_is_struct(S) {
    flags, subcommand_offset, subcommands := type_to_flags(S)
    defer delete(flags)
    defer for &flag in flags {
        flag_delete(&flag)
    }

    args := os.args

    program := args[0]
    pos := 0
    subcommand: Maybe(string)

    outer_loop:for i := 1; i < len(args); i += 1 {
        arg := args[i]
        if strings.has_prefix(arg, "--") {
            arg_without_prefix := strings.trim_prefix(arg, "--")

            found := false
            for flag in flags {
                if flag.name == arg_without_prefix {
                    if flag.type == bool {
                        (cast(^bool)(cast(uintptr)out + flag.offset))^ = true
                        continue outer_loop
                    }

                    i += 1
                    if i >= len(args) {
                        fmt.eprintfln("Unexpected end of arguments")
                        print_usage(program, subcommands, flags[:])
                        ok = false
                        return
                    }

                    flag_string_value := args[i]
                    switch flag.type {
                    case string:
                        (cast(^string)(cast(uintptr)out + flag.offset))^ = flag_string_value
                    case:
                        fmt.panicf("TODO: Unhandled flag type {}", flag.type)
                    }

                    found := true
                    break
                }
            }

            if !found {
                fmt.eprintfln("Unknown flag {}", arg)
                print_usage(program, subcommands, flags[:])
                ok = false
                return
            }
        } else if strings.has_prefix(arg, "-") {
            arg_without_prefix := strings.trim_prefix(arg, "-")
            fmt.panicf("TODO: short flags")
        }

        if pos == 0 {
            found := false
            for subcommand_ in subcommands {
                if arg == subcommand_.name {
                    subcommand = subcommand_.name
                    (cast(^reflect.Type_Info_Enum_Value)(cast(uintptr)out + subcommand_offset))^ = subcommand_.value
                    found = true
                    break
                }
            }

            if !found {
                fmt.eprintfln("Expected subcommand")
                print_usage(program, subcommands, flags[:])
                ok = false
                return
            }
        } else {
            fmt.panicf("TODO: positional arguments")
        }
    }

    return true
}
