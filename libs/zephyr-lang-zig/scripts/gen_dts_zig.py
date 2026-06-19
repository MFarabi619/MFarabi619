#!/usr/bin/env python3
#
# Derived from zig-zephyr (https://github.com/rcrnstn/zig-zephyr),
# Copyright (c) 2021 Nordic Semiconductor ASA, Apache-2.0.
#
# Walks the EDT pickle Zephyr produces during DTS processing and emits an
# idiomatic Zig module that mirrors the devicetree as nested struct/const
# data. Phandles become real Zig references. `__device_dts_ord_N` externs
# (declared by Zephyr's DEVICE_DT_* macros) are declared up front as
# opaque externs so the generated module is self-contained — no @cImport
# of Zephyr headers required.

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

    with open(args.edt_pickle, "rb") as f:
        edt = pickle.load(f)

    ordinals = sorted(
        node.dep_ordinal
        for node in edt.nodes
        if "status" in node.props and node.props["status"].val == "okay"
    )

    with open(args.zig_out, "w", encoding="utf-8") as zig_out:
        print("pub const Device = opaque {};", file=zig_out)
        for ordinal in ordinals:
            print(f"pub extern const __device_dts_ord_{ordinal}: Device;", file=zig_out)
        print("", file=zig_out)
        print(print_node_props_and_children(edt.scc_order[0][0], 0, True), file=zig_out)


def ident(level):
    return " " * (4 * level)


def print_node_props_and_children(node, level, decl):
    s = ""
    if "status" in node.props and node.props["status"].val == "okay":
        s += ident(level)
        s += "const _device = " if decl else "._device = "
        s += f"&__device_dts_ord_{node.dep_ordinal}"
        s += ";\n" if decl else ",\n"
    for prop_name, prop in node.props.items():
        prop_id = str2ident(prop_name)
        val = prop2value(prop)
        if val is None:
            s += ident(level) + f"// {prop.type}" + "\n"
        s += ident(level)
        s += "const " if decl else "."
        s += f"{prop_id} = "
        if val is not None:
            s += f"{val}"
        else:
            s += "undefined"
        s += ";\n" if decl else ",\n"
    for child in node.children.values():
        child_decl = True if str2ident(child.name) == "soc" else False
        s += ident(level)
        s += f"// {child.dep_ordinal}\n"
        s += ident(level)
        if decl:
            if level == 0:
                s += "pub "
            s += "const "
        else:
            s += "."
        s += f"{str2ident(child.name)} = "
        s += "struct {" if child_decl else ".{"
        s += "\n"
        s += print_node_props_and_children(child, level + 1, child_decl)
        s += ident(level)
        s += "};\n" if decl else "},\n"
    return s


def prop2value(prop):
    if prop.type == "string":
        return quote_str(prop.val)
    if prop.type == "int":
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


def path2ref(p):
    return "&" + re.sub("[/]", ".", re.sub("[-,.@+]", "_", p[1:].lower()))


def str2ident(s):
    return re.sub("[-,.@/+]", "_", s.lower())


def list2init(l):
    return "{" + ", ".join(l) + "}"


def quote_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


if __name__ == "__main__":
    main()
