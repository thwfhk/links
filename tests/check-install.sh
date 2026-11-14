#!/usr/bin/env bash
set -eu

if [[ $# -ne 1 || $1 != /* || ! -x $1 ]]; then
    echo "Usage: $0 /absolute/path/to/linx" >&2
    exit 2
fi

installed=$1
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/smalllinks-install.XXXXXX")
trap 'rm -rf -- "$work_dir"' EXIT
cp tests/stdlibtests/binaryTree/inorder.links "$work_dir/imports.links"
cd "$work_dir"
unset LINKS_CONFIG

check_output() {
    local expected=$1 actual
    shift
    actual=$("$installed" "$@")
    if [[ "$actual" != "$expected" ]]; then
        printf 'Expected %s, got %s\n' "$expected" "$actual" >&2
        exit 1
    fi
    printf 'SUCCESS: %s\n' "$actual"
}

check_output '[42] : List Int' -e 'map(fun(x) { x + 2 }, [40])'
check_output '"[1,2,3,4]" : String' imports.links
