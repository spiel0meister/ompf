package ompf

import "core:c"
import "core:fmt"
import "core:strings"
import "core:strconv"
import "core:os"
import "core:io"
import "core:math"
import "base:runtime"

import git2 "libgit2"
import toml "./toml_parser"

VERSION :string: #config(VERSION, "this should not happen")

OMPF_CONFIG_FILENAME :: "ompf.toml"

print_toml_error :: proc(err: toml.Error) -> bool {
    if err.type == .None {
        return false
    }

    fmt.eprintfln("Toml error {}: {}", err.type, err.more)
    return true
}

print_git2_last_error :: proc() -> bool {
    error := git2.error_last()
    if error.klass == .None {
        return false
    }

    fmt.eprintfln("libgit2 error {}: {}", error.klass, error.message)
    return true
}

Version :: distinct string
Branch :: distinct string
Commit :: distinct string
Target :: union {
    Version,
    Branch,
    Commit,
}

Package :: struct {
    name, path, url: string,
    target: Target,
    dependencies: [dynamic]Package,
}

package_destroy :: proc(pakage: ^Package) {
    defer delete(pakage.dependencies)
    defer for &dep in pakage.dependencies {
        package_destroy(&dep)
    }
    delete(pakage.path)
}

clone_repo :: proc(pakage, name, url: string) -> (bool) {
    opts := git2.Clone_Options{}
    git2.clone_options_init(&opts, git2.VERSION)

    name_copy := name
    clone_progress_cb :: proc "c" (path: cstring, completed_steps: c.size_t, total_steps: c.size_t, payload: rawptr) {
        name := cast(^string)payload

        context = runtime.default_context()
        percent := f32(completed_steps) / f32(total_steps)
        fmt.printf("%s %02f%%\r", name^, math.floor(percent * 100))

        if percent == 1 {
            fmt.printf("\n")
        }
    }
    opts.checkout_opts.progress_cb = clone_progress_cb
    opts.checkout_opts.progress_payload = &name_copy

    curl := strings.clone_to_cstring(url, context.temp_allocator)

    path := fmt.tprintf("{}/deps/{}", pakage, name)
    cpath := strings.clone_to_cstring(path, context.temp_allocator)

    repo: ^git2.Repository
    defer git2.repository_free(repo)

    if ret := git2.clone(&repo, curl, cpath, &opts); ret < 0 {
        last_error := git2.error_last()
        if last_error.klass != .Invalid {
            git2.print_error(last_error)
            return false
        } else {
            return true
        }
    }

    fmt.printfln("Repo {} cloned to {}", name, path)
    return true
}

open_dep_repo :: proc(pakage, name: string) -> (repo: ^git2.Repository, ok := true) {
    path := fmt.tprintf("{}/deps/{}", pakage, name)
    cpath := strings.clone_to_cstring(path, context.temp_allocator)

    if ret := git2.repository_open(&repo, cpath); ret < 0 {
        last_error := git2.error_last()
        git2.print_error(last_error)
        ok = false
        return
    }

    return
}

collect_dependencies :: proc(pakage: ^Package, allocator := context.allocator) -> bool {
    ompf_toml := fmt.tprintf("{}/{}", pakage.path, OMPF_CONFIG_FILENAME)
    if !os.exists(ompf_toml) {
        return true
    }

    parsed_file, err := toml.parse_file(ompf_toml)
    if print_toml_error(err) { return false }

    for name, section in parsed_file {
        if name == "deps" {
            for dep_name, dep_section in section.(^toml.Table) {
                url := toml.get_string_panic(dep_section.(^toml.Table), "url")

                dep := Package{
                    name = dep_name,
                    url = url,
                }
                dep.path = strings.clone(fmt.tprintf("{}/deps/{}", pakage.path, dep.name), allocator)

                version, is_version := toml.get_string(dep_section.(^toml.Table), "version")
                if is_version {
                    dep.target = Version(version)
                    append(&pakage.dependencies, dep)
                    continue
                } 

                branch, is_branch := toml.get_string(dep_section.(^toml.Table), "branch")
                if is_branch {
                    dep.target = Branch(branch)
                    append(&pakage.dependencies, dep)
                    continue
                }

                commit := toml.get_string_panic(dep_section.(^toml.Table), "commit")
                dep.target = Commit(commit)
                append(&pakage.dependencies, dep)
            }
        } else {
            fmt.eprintfln("Unknown section {}", name)
        }
    }

    for &dep in pakage.dependencies {
        clone_repo(pakage.path, dep.name, dep.url) or_return
        collect_dependencies(&dep) or_return
    }

    return true
}

checkout_package :: proc(pakage: ^Package, root := true) -> (bool) {
    if !root {
        cpath := strings.clone_to_cstring(pakage.path, context.temp_allocator)

        repo: ^git2.Repository
        if ret := git2.repository_open(&repo, cpath); ret < 0 {
            last_error := git2.error_last()
            git2.print_error(last_error)
            return false
        }

        tags: git2.Str_Array
        defer git2.strarray_dispose(&tags)

        switch v in pakage.target {
        case Commit:
            oid: git2.Object_Id
            if ret := git2.oid_fromstr(&oid, strings.clone_to_cstring(auto_cast v, context.temp_allocator)); ret < 0 {
                print_git2_last_error()
            }

            commit: ^git2.Object
            if ret := git2.object_lookup(&commit, repo, &oid, .Commit); ret < 0 {
                print_git2_last_error()
            }

            if ret := git2.checkout_tree(repo, commit, nil); ret < 0 {
                print_git2_last_error()
            }

            fmt.println("{}: Switched to commit {}", cast(string)v)
        case Version:
            cversion := strings.clone_to_cstring(string(pakage.target.(Version)), context.temp_allocator)
            if ret := git2.tag_list_match(&tags, cversion, repo); ret < 0 {
                print_git2_last_error()
                return false
            }

            if tags.size == 0 {
                fmt.eprintfln("Repo {} does not have tags. Use `branch` or `commit` instead of `version`", pakage.url)
                return false
            }

            best_tag_name := tags.items[tags.size - 1]
            best_tag_path := fmt.tprintf("{}/.git/refs/tags/{}", pakage.path, best_tag_name)

            oid_raw, ok2 := os.read_entire_file(best_tag_path)
            assert(ok2)

            oid_string := string(oid_raw)
            oid_string = strings.trim_space(oid_string)
            coid_string := strings.clone_to_cstring(oid_string, context.temp_allocator)

            oid: git2.Object_Id
            if ret := git2.oid_fromstr(&oid, coid_string); ret < 0 {
                print_git2_last_error()
                return false
            }

            tag_object: ^git2.Object 
            defer git2.object_free(tag_object)

            if ret := git2.object_lookup(&tag_object, repo, &oid, .Commit); ret < 0 {
                print_git2_last_error()
                return false
            }

            if ret := git2.checkout_tree(repo, tag_object, nil); ret < 0 {
                last_error := git2.error_last()
                if last_error.klass != .Checkout {
                    git2.print_error(last_error)
                    return false
                }
            }

            fmt.printfln("{}: Switched to tag {}", pakage.name, best_tag_name)
        case Branch:
            cbranch := strings.clone_to_cstring(string(pakage.target.(Branch)), context.temp_allocator)

            ref: ^git2.Reference
            defer git2.reference_free(ref)

            if ret := git2.branch_lookup(&ref, repo, cbranch, .Local); ret < 0 {
                print_git2_last_error()
                return false
            }

            oid := git2.reference_target(ref)

            object: ^git2.Object
            defer git2.object_free(object)

            if ret := git2.object_lookup(&object, repo, oid, .Commit); ret < 0 {
                print_git2_last_error()
                return false
            }

            if ret := git2.checkout_tree(repo, object, nil); ret < 0 {
                print_git2_last_error()
                return false
            }

            fmt.printfln("{}: switched branch to {}", pakage.name, string(pakage.target.(Branch)))
        }

    }

    for &dep in pakage.dependencies {
        checkout_package(&dep, false) or_return
    }

    return true
}

list_pakages :: proc(pakage: ^Package, indent := 0, h := os.stdout) {
    whitespace := strings.repeat(" ", indent, context.temp_allocator)

    fmt.fprintf(h, "{}{} | ", whitespace, pakage.name)
    switch v in pakage.target {
    case Version:
        fmt.fprintfln(h, "version {}", v)
    case Branch:
        fmt.fprintfln(h, "branch {}", v)
    case Commit:
        fmt.fprintfln(h, "commit {}", v)
    }
    for &dep in pakage.dependencies {
        list_pakages(&dep, indent + 4)
    }
}

Subcommand :: enum {
    Checkout,
    List,
}

Args :: struct {
    subcommand: Subcommand,
    version: bool `no_subcommand usage:"Display version" alias:"v"`,
}

main :: proc() {
    args: Args

    program, parsed_args := parse_args(&args)
    if !parsed_args {
        os.exit(1)
    }

    if args.version {
        fmt.printfln("{} version {}", program, VERSION)
        return
    }

    git2.init()
    defer git2.shutdown()

    global_section, err1 := toml.parse_file(OMPF_CONFIG_FILENAME)
    if print_toml_error(err1) {
        os.exit(1)
    }

    actual_path, err := os.absolute_path_from_relative(".")
    assert(err == nil)

    name := actual_path
    for i := len(actual_path) - 1; i >= 0; i -= 1 {
        if actual_path[i] == '/' {
            name = actual_path[i + 1:]
            break
        }
    }

    pakage := Package{
        name = name,
        path = actual_path,
        target = Branch("main"),
    }
    defer package_destroy(&pakage)

    if !collect_dependencies(&pakage) {
        os.exit(1)
    }

    switch args.subcommand {
    case .Checkout:
        if !checkout_package(&pakage) {
            os.exit(1)
        }
    case .List:
        list_pakages(&pakage)
    }
}
