#!/usr/bin/env python3
#
# Derived from zig-zephyr (https://github.com/rcrnstn/zig-zephyr),
# Copyright (c) 2021 Nordic Semiconductor ASA, Apache-2.0.
#
# Walks the EDT pickle Zephyr produces during DTS processing and emits a
# Zig module that mirrors the devicetree as flat top-level constants.
# Every node becomes `pub const <flat_name> = .{...};` — phandle refs
# point at these flat names, so no nested-comptime-field issues even
# when siblings cross-reference (e.g. ESP32-S3's soc children).
# `__device_dts_ord_N` externs (declared by Zephyr's DEVICE_DT_* macros)
# are declared up front as opaque externs so the generated module is
# self-contained — no @cImport of Zephyr headers required.

import argparse
import os
import pickle
import sys
import re


def parse_args():
    p = argparse.ArgumentParser(allow_abbrev=False)
    p.add_argument("--zig-out", required=True)
    p.add_argument("--edt-pickle", required=True)
    p.add_argument("--edt-lib", required=True)
    return p.parse_args()


def main():
    global zig_out
    args = parse_args()
    sys.path.insert(0, args.edt_lib)
    sys.path.insert(0, os.path.dirname(os.path.dirname(args.edt_lib)))
    import edtlib_logger
    edtlib_logger.setup_edtlib_logging()

    with open(args.edt_pickle, "rb") as f:
        edt = pickle.load(f)

    ordinals = sorted(
        node.dep_ordinal
        for node in edt.nodes
        if node.status == "okay"
    )

    with open(args.zig_out, "w", encoding="utf-8") as zig_out:
        print('pub const sys = @import("sys");', file=zig_out)
        for ordinal in ordinals:
            print(f"pub extern const __device_dts_ord_{ordinal}: sys.struct_device;", file=zig_out)
        print("", file=zig_out)
        for node in edt.nodes:
            if node.path == "/":
                continue
            if node.path == "/aliases":
                continue
            print(f"// {node.dep_ordinal}", file=zig_out)
            print(f"pub const {path2ident(node.path)} = .{{", file=zig_out)
            print(emit_node_props(node, 1), end="", file=zig_out)
            print("};", file=zig_out)
        print("pub const aliases = .{", file=zig_out)
        for node in edt.nodes:
            for alias_name in node.aliases:
                print(f"    .{str2ident(alias_name)} = {path2ref(node.path)},", file=zig_out)
        print("};", file=zig_out)


def ident(level):
    return " " * (4 * level)


def emit_node_props(node, level):
    s = ""
    if node.status == "okay":
        s += ident(level) + f"._device = &__device_dts_ord_{node.dep_ordinal},\n"
    for prop_name, prop in node.props.items():
        prop_id = str2ident(prop_name)
        val = prop2value(prop)
        if val is None:
            s += ident(level) + f"// {prop.type}\n"
        s += ident(level) + f".{prop_id} = "
        if val is not None:
            s += f"{val}"
        else:
            s += "undefined"
        s += ",\n"
    return s


def prop2value(prop):
    if prop.type == "string":
        return quote_str(prop.val)
    if prop.type == "int":
        if prop.val < 0:
            return f"@as(i32, {prop.val})"
        return f"@as(u32, {prop.val})"
    if prop.type == "boolean":
        return "true" if prop.val else "false"
    if prop.type == "array":
        return "[_]u32" + list2init(f"{hex(v)}" for v in prop.val)
    if prop.type == "uint8-array":
        return "[_]u8" + list2init(f"{hex(v)}" for v in prop.val)
    if prop.type == "string-array":
        return "[_][]const u8" + list2init(quote_str(v) for v in prop.val)
    if prop.type == "phandle":
        return path2ref(prop.val.path)
    if prop.type == "phandles":
        return "." + list2init(path2ref(n.path) for n in prop.val)
    if prop.type == "phandle-array":
        return pharray2items(prop.val)
    return None


def pharray2items(val):
    s = ""
    if len(val) > 1:
        s += ".{"
    for i, entry in enumerate(val):
        if entry is None:
            continue
        if i > 0:
            s += ", "
        s += ".{"
        s += f".ph={path2ref(entry.controller.path)}"
        for cell, v in entry.data.items():
            s += "," + "." + str2ident(cell) + "=" + f"@as(u32, {v})"
        s += "}"
    if len(val) > 1:
        s += "}"
    return s


def path2ident(p):
    return re.sub("[-/,.@+]", "_", p[1:].lower())


def path2ref(p):
    return "&" + path2ident(p)


def str2ident(s):
    return re.sub("[-,.@/+]", "_", s.lower())


def list2init(items):
    return "{" + ", ".join(items) + "}"


def quote_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


if __name__ == "__main__":
    main()
