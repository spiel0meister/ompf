package ompf

import "core:fmt"
import "core:strings"
import "core:strconv"

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

Dependency :: struct {
    name, url, version: string,
}

clone_repo :: proc(name, url: string) -> (^git2.Repository, bool) {
    opts := git2.Clone_Options{}
    git2.clone_options_init(&opts, 1)

    curl := strings.clone_to_cstring(url, context.temp_allocator)

    path := fmt.tprintf("./vendor/{}", name)
    cpath := strings.clone_to_cstring(path, context.temp_allocator)

    repo: ^git2.Repository
    ret := git2.clone(&repo, curl, cpath, &opts)
    defer git2.repository_free(repo)

    if ret < 0 {
        last_error := git2.error_last()
        fmt.eprintfln("Couldn't clone library {}: {}", name, last_error.message)
        return nil, false
    }

    fmt.printfln("Repo {} cloned to {}", url, path)
    return repo, true
}

main :: proc() {
    git2.init()
    defer git2.shutdown()

    global_section, err1 := toml.parse_file(OMPF_CONFIG_FILENAME)
    if print_toml_error(err1) {
        return
    }

    for name, section in global_section {
        url := toml.get_string_panic(section.(^toml.Table), "url")
        version := toml.get_string_panic(section.(^toml.Table), "version")

        dep := Dependency{
            name = name,
            url = url,
            version = version,
        }

        fmt.println(dep)
    }
}
