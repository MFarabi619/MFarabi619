from os.path import join
import fileinput
import re

Import("env")

for line in fileinput.input(
    (
        lambda: join(
            env.subst("$PROJECT_LIBDEPS_DIR"),
            env["PIOENV"],
            "Sqlite3Esp32",
            "src",
            "config_ext.h",
        )
    )(),
    inplace=True,
):
    print(
        re.sub(r"^\s*#define\s+YYSTACKDEPTH\s+\d+", "#define YYSTACKDEPTH 30", line),
        end="",
    )
