package ompf

import "core:fmt"
import "core:strings"

import git2 "libgit2"
import toml "./vendor/toml_parser"

clone_repo :: proc(user, name: string) -> bool {
    opts := git2.Clone_Options{}
    git2.clone_options_init(&opts, 1)

    url := fmt.tprintf("https://github.com/{}/{}", user, name)
    curl := strings.clone_to_cstring(url, context.temp_allocator)

    path := fmt.tprintf("./vendor/{}", name)
    cpath := strings.clone_to_cstring(path, context.temp_allocator)

    repo: ^git2.Repository
    ret := git2.clone(&repo, curl, cpath, &opts)
    defer git2.repository_free(repo)

    if ret < 0 {
        last_error := git2.error_last()
        fmt.eprintfln("Couldn't clone library {}: {}", name, last_error.message)
        return false
    }

    return true
}

main :: proc() {
    git2.init()
    defer git2.shutdown()

    if !clone_repo("Up05", "toml_parser") {
        return
    }
}
