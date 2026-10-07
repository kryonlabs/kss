#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo"
ziran=${ZIRAN:-ziran}
toolchain=$("$ziran" pkg path ziran)
kryon=$("$ziran" pkg path kryon)
build=$repo/build/css-export
mkdir -p "$build"
exec 9>"$build/lock"
flock 9
"$ziran" ir --root tests --module-path src --module-path "kryon=$kryon/src/ui" \
    --module-path "$toolchain/std" -o "$build/ir" tests/css_export_behavior.zi
for source in source saved; do
    input=$repo/tests/css_export_behavior.zi
    root=$repo/tests
    if [ "$source" = saved ]; then input=$build/ir/css_export_behavior.zir; root=$build/ir; fi
    for target in c cpp go; do
        output=$build/$source-$target
        "$ziran" build --root "$root" --module-path src --module-path "kryon=$kryon/src/ui" \
            --module-path "$toolchain/std" --module-path "$build/ir" --no-main \
            --target="$target" --entry css_export_behavior:Answer -o "$output" "$input"
        if [ "$target" = go ]; then
            rm -f "$output/driver.go"
            printf 'package ziran\nimport "testing"\nfunc TestCSSExport(t *testing.T) { if CssExportBehavior_Answer() != 42 { t.Fatal("CSS export") } }\n' >"$output/driver_test.go"
            (cd "$output" && GO111MODULE=off go test .)
        else
            compiler=${CC:-cc}; suffix=c; header=h; standard=c11
            if [ "$target" = cpp ]; then compiler=${CXX:-c++}; suffix=cpp; header=hpp; standard=c++17; fi
            printf '#include "css_export_behavior.%s"\nint main(void) { return Answer() == 42 ? 0 : 1; }\n' "$header" >"$output/driver.$suffix"
            "$compiler" -std="$standard" -O2 -I"$toolchain/include" -I"$output" \
                "$output"/*."$suffix" -o "$output/run"
            "$output/run"
        fi
    done
done
echo 'KSS CSS export: source/saved IR, C/C++/Go PASS'
