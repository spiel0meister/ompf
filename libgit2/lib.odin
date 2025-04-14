package libgit2
// what the fuck?

import "core:c"
import "core:fmt"
foreign import lib {
    "system:git2",
    "system:ssl",
    "system:crypto",
}

Error_Klass :: enum c.int {
    None = 0,
    No_Memory = 1,
    Os = 2,
    Invalid = 3,
    Reference = 4,
    Zlib = 5,
    Repository = 6,
    Config = 7,
    Regex = 8,
    Odb = 9,
    Index = 10,
    Object = 11,
    Net = 12,
    Tag = 13,
    Tree = 14,
    Indexer = 15,
    Ssl = 16,
    Submodule = 17,
    Thread = 18,
    Stash = 19,
    Checkout = 20,
    Fetchhead = 21,
    Merge = 22,
    Ssh = 23,
    Filter = 24,
    Revert = 25,
    Callback = 26,
    Cherrypick = 27,
    Describe = 28,
    Rebase = 29,
    Filesystem = 30,
    Patch = 31,
    Worktree = 32,
    Sha = 33,
    Http = 34,
    Internal = 35,
    Grafts = 36,
}

Error :: struct {
    message: cstring,
    klass: Error_Klass,
}

Repository :: struct {}
Reference :: struct {}
Tree :: struct {}
Object :: struct {}
Index :: struct {}
Tag :: struct {}
Object_Id :: [20]u8

Object_Type :: enum c.int {
    Any = -2,
    Invalid = -1,
    Commit = 1,
    Tree = 2,
    Blob = 3,
    Tag = 4,
}

Branch_Type :: enum c.int {
    Local = 1,
    Remote = 2,
    All = 3,
}

Tag_Foreach_Callback :: proc "c" (name: cstring, oid: ^Object_Id, payload: rawptr) -> c.int

Str_Array :: struct {
    items: [^]cstring,
    size: c.size_t,
}

Checkout_Options :: struct {
    version: c.uint,
    checkout_strategy: c.uint,
    disable_filters: c.int,
    dir_mode: c.uint,
    file_mode: c.uint,
    file_open_flags: c.int,
    notify_flags: c.uint,
    notify_cb: rawptr,
    notify_payload: rawptr,
    progress_cb: rawptr,
    progress_payload: rawptr,
    paths: Str_Array,
    baseline: ^Tree,
    baseline_index: ^Index,
    target_directory: cstring,
    ancestor_label: cstring,
    our_label: cstring,
    their_label: cstring,
    perfdata_cb: rawptr,
    perfdata_payload: rawptr,
}

Fetch_Prune :: enum c.int {
    Unspecified = 0,
    Prune = 1,
    No_Prune = 2,
}

Autotag_Option :: enum c.int {
    Unspecified = 0,
    Auto = 1,
    None = 2,
    All = 3
}

Remote_Redirect :: enum c.int {
    None = 1 << 0,
    Initial = 1 << 1,
    All = 1 << 2,
}

Remote_Callbacks :: struct {
    version: c.uint,
    sideband_progress: rawptr,
    completion: proc(int, rawptr) -> c.int,
    credentials: rawptr,
    certificate_check: rawptr,
    transfer_progress: rawptr,
    indexer_progress: rawptr,
    update_tips: proc(cstring, rawptr, rawptr, rawptr) -> c.int,
    pack_progress: rawptr,
    push_transfer_progress: rawptr,
    push_update_reference: rawptr,
    push_negotiation: rawptr,
    transport: rawptr,
    remote_ready: rawptr,
    payload: rawptr,
    resolve_url: rawptr,
    update_refs: proc(cstring, rawptr, rawptr, rawptr, rawptr) -> c.int,
}

Proxy_Type :: enum c.int {
    None = 0,
    Auto,
    Specified,
}

Proxy_Options :: struct {
    version: c.uint,
    type: Proxy_Type,
    url: cstring,
    credentials: rawptr,
    certificate_check: rawptr,
    payload: rawptr,
}

Fetch_Options :: struct {
    version: c.int,
    callbacks: Remote_Callbacks,
    prune: Fetch_Prune,
    update_fetchhead: c.uint,
    download_tags: Autotag_Option,
    git_proxy_options: Proxy_Options,
    depth: c.int,
    git_remote_redirect_t: Remote_Redirect,
    custom_headers: Str_Array,
}

Clone_Local :: enum c.int {
    Auto = 0,
    Local = 1,
    No_Local = 2,
    Local_No_Links = 3
}

Clone_Options :: struct {
    version: c.uint,
    checkout_opts: Checkout_Options,
    fetch_opts: Fetch_Options,
    bare: c.int,
    local: Clone_Local,
    checkout_branch: cstring,
    repository_cb: rawptr,
    repository_cb_payload: rawptr,
    remote_cb: rawptr,
    remote_cb_payload: rawptr,
}

print_error :: proc(error: ^Error, loc := #caller_location) -> bool {
    if error.klass == .None {
        return false
    }

    fmt.eprintfln("{}:{}: libgit2 error {}: {}", loc.file_path, loc.line, error.klass, error.message)
    return true
}

@(default_calling_convention="c", link_prefix="git_libgit2_")
foreign lib {
    init :: proc() ---
    shutdown :: proc() ---
}

@(default_calling_convention="c", link_prefix="git_")
foreign lib {
    error_last :: proc() -> ^Error ---
    strarray_dispose :: proc(array: ^Str_Array) ---

    repository_open :: proc(out: ^^Repository, path: cstring) -> c.int ---
    repository_free :: proc(repo: ^Repository) ---

    clone_options_init :: proc(opts: ^Clone_Options, version: c.uint) -> c.int ---
    clone :: proc(out: ^^Repository, url, local_path: cstring, options: ^Clone_Options) -> c.int ---

    checkout_tree :: proc(repo: ^Repository, treeish: ^Object, options: ^Checkout_Options) -> c.int ---

    oid_fromstr :: proc(oid: ^Object_Id, str: cstring) -> c.int ---

    object_lookup :: proc(out: ^^Object, repo: ^Repository, oid: ^Object_Id, type: Object_Type) -> c.int ---
    object_free :: proc(object: ^Object) ---

    branch_lookup :: proc(out: ^^Reference, repo: ^Repository, name: cstring, type: Branch_Type) -> c.int ---

    reference_target :: proc(ref: ^Reference) -> ^Object_Id ---
    reference_free :: proc(ref: ^Reference) ---

    tag_lookup :: proc(out: ^^Tag, repo: ^Repository, oid: ^Object_Id) -> c.int ---
    tag_list :: proc(names: ^Str_Array, repo: ^Repository) -> c.int ---
    tag_list_match :: proc(names: ^Str_Array, pattern: cstring, repo: ^Repository) -> c.int ---
    tag_target :: proc(out: ^^Object, tag: ^Tag) -> c.int ---
    tag_foreach :: proc(repo: ^Repository, cb: Tag_Foreach_Callback, payload: rawptr) -> c.int ---
}

