package ompf

import "core:c"
import "core:fmt"
import "core:strings"
import "core:strconv"
import "core:os"
import "core:io"
import "core:flags"
import "core:flags/example"
import "base:runtime"

import git2 "libgit2"
import toml "./vendor/toml_parser"

OMPF_CONFIG_FILENAME :: "ompf.toml"

print_toml_error :: proc(err: toml.Error) -> bool {
    if err.type == .None {
        return false
    }

    fmt.eprintfln("Toml error {}: {}", err.type, err.more)
    return true
}

Version :: distinct string
Branch :: distinct string
Target :: union {
    Version,
    Branch
}

Dependency :: struct {
    name, url: string,
    target: Target,
}

clone_or_open_repo :: proc(name, url: string) -> (^git2.Repository, bool) {
    opts := git2.Clone_Options{}
    git2.clone_options_init(&opts, 1)

    curl := strings.clone_to_cstring(url, context.temp_allocator)

    path := fmt.tprintf("./vendor/{}", name)
    cpath := strings.clone_to_cstring(path, context.temp_allocator)

    repo: ^git2.Repository
    if ret := git2.clone(&repo, curl, cpath, &opts); ret < 0 {
        last_error := git2.error_last()
        if last_error.klass != .Invalid {
            git2.print_error(last_error)
            return nil, false
        } else {
            ret = git2.repository_open(&repo, cpath)
            assert(ret == 0)

            fmt.printfln("Repo {} already cloned", name)
            return repo, true
        }
    }

    fmt.printfln("Repo {} cloned to {}", name, path)
    return repo, true
}

Options :: struct {
    command: string `args:"pos=0,required" usage:"Command to execute"`,
}

main :: proc() {
    options: Options
    if err := flags.parse(&options, os.args[1:]); err != nil {
        fmt.eprintln("Couldn't parse args")
        flags.write_usage(io.to_writer(os.stream_from_handle(os.stdout)), Options, os.args[0])
        return
    }

    if options.command == "fetch" {
        git2.init()
        defer git2.shutdown()

        global_section, err1 := toml.parse_file(OMPF_CONFIG_FILENAME)
        if print_toml_error(err1) {
            return
        }

        dependencies: [dynamic]Dependency
        defer delete(dependencies)

        for name, section in global_section {
            url := toml.get_string_panic(section.(^toml.Table), "url")

            dep := Dependency{
                name = name,
                url = url,
            }

            version, is_version := toml.get_string(section.(^toml.Table), "version")
            if is_version {
                dep.target = Version(version)
            } else {
                dep.target = Branch(toml.get_string_panic(section.(^toml.Table), "branch"))
            }

            append(&dependencies, dep)
        }

        for dep in dependencies {
            repo, ok := clone_or_open_repo(dep.name, dep.url)
            if !ok {
                continue
            }
            defer git2.repository_free(repo)

            tags: git2.Str_Array
            defer git2.strarray_dispose(&tags)

            switch v in dep.target {
            case Version:
                cversion := strings.clone_to_cstring(string(dep.target.(Version)), context.temp_allocator)
                if ret := git2.tag_list_match(&tags, cversion, repo); ret < 0 {
                    last_error := git2.error_last()
                    git2.print_error(last_error)
                    continue
                }

                if tags.size == 0 {
                    fmt.panicf("Repo {} does not have tags. Use `branch` instead of `version`", dep.url)
                }

                best_tag_name := tags.items[tags.size - 1]
                best_tag_path := fmt.tprintf("./vendor/{}/.git/refs/tags/{}", dep.name, best_tag_name)

                oid_raw, ok2 := os.read_entire_file(best_tag_path)
                assert(ok2)

                oid_string := string(oid_raw)
                oid_string = strings.trim_space(oid_string)
                coid_string := strings.clone_to_cstring(oid_string, context.temp_allocator)

                oid: git2.Object_Id
                if ret := git2.oid_fromstr(&oid, coid_string); ret < 0 {
                    last_error := git2.error_last()
                    git2.print_error(last_error)
                    continue
                }

                tag_object: ^git2.Object 
                defer git2.object_free(tag_object)

                if ret := git2.object_lookup(&tag_object, repo, &oid, .Commit); ret < 0 {
                    last_error := git2.error_last()
                    git2.print_error(last_error)
                    continue
                }

                if ret := git2.checkout_tree(repo, tag_object, nil); ret < 0 {
                    last_error := git2.error_last()
                    if last_error.klass != .Checkout {
                        git2.print_error(last_error)
                        continue
                    }
                }

                fmt.printfln("Switched {} to {}", dep.name, best_tag_name)
            case Branch:
                cbranch := strings.clone_to_cstring(string(dep.target.(Branch)), context.temp_allocator)

                ref: ^git2.Reference
                defer git2.reference_free(ref)

                if ret := git2.branch_lookup(&ref, repo, cbranch, .Local); ret < 0 {
                    error := git2.error_last()
                    git2.print_error(error)
                    continue
                }

                oid := git2.reference_target(ref)

                object: ^git2.Object
                defer git2.object_free(object)

                if ret := git2.object_lookup(&object, repo, oid, .Commit); ret < 0 {
                    error := git2.error_last()
                    git2.print_error(error)
                    continue
                }

                if ret := git2.checkout_tree(repo, object, nil); ret < 0 {
                    error := git2.error_last()
                    git2.print_error(error)
                    continue
                }

                fmt.printfln("Switched {} to branch {}", dep.name, string(dep.target.(Branch)))
            }
        }
    } else {
        fmt.eprintfln("Unknown command {}", options.command)
        return
    }
}
