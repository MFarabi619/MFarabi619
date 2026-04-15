#include "coreutils.h"
#include "console/icons.h"
#include "console/path.h"
#include "console/prompt.h"

#include <SD.h>
#include <stdio.h>
#include <string.h>

namespace {

//------------------------------------------
//  File type → icon + color
//------------------------------------------
struct FileType {
  const char *ext;
  const char *icon;
  const char *color;
};

const FileType file_types[] = {
  {"rs",   NF_DEV_RUST,       "\x1b[33m"},
  {"toml", NF_SETI_TOML,      "\x1b[32m"},
  {"json", NF_SETI_JSON,      "\x1b[32m"},
  {"csv",  NF_FA_DATABASE,    "\x1b[36m"},
  {"db",   NF_FA_DATABASE,    "\x1b[36m"},
  {"txt",  NF_FA_FILE_TEXT,   "\x1b[0m"},
  {"log",  NF_FA_FILE_TEXT,   "\x1b[0m"},
  {"md",   NF_SETI_MARKDOWN,  "\x1b[1;33m"},
  {"org",  NF_SETI_ORG,       "\x1b[1;33m"},
  {"html", NF_DEV_HTML5,      "\x1b[35m"},
  {"js",   NF_DEV_JAVASCRIPT, "\x1b[33m"},
  {"css",  NF_DEV_CSS3,       "\x1b[35m"},
  {"wasm", NF_SETI_WASM,      "\x1b[35m"},
  {"png",  NF_FA_FILE_IMAGE,  "\x1b[35m"},
  {"jpg",  NF_FA_FILE_IMAGE,  "\x1b[35m"},
  {"svg",  NF_FA_FILE_IMAGE,  "\x1b[35m"},
  {"bin",  NF_MD_BINARY,      "\x1b[2m"},
  {"dat",  NF_MD_BINARY,      "\x1b[2m"},
  {"nix",  NF_LINUX_NIX,      "\x1b[34m"},
};

struct DirType {
  const char *name;
  const char *icon;
};

const DirType dir_types[] = {
  {"home",      NF_FA_HOME},
  {".config",   NF_SETI_CONFIG},
  {".ssh",      NF_MD_SSH},
  {"data",      NF_FA_DATABASE},
};

const char *DIR_COLOR = "\x1b[1;34m";

const char *file_ext(const char *name) {
  const char *dot = strrchr(name, '.');
  return dot ? dot + 1 : nullptr;
}

void lookup_file(const char *name, const char **icon, const char **color) {
  const char *ext = file_ext(name);
  if (ext) {
    for (auto &ft : file_types) {
      if (strcasecmp(ext, ft.ext) == 0) {
        *icon = ft.icon;
        *color = ft.color;
        return;
      }
    }
  }
  *icon = NF_FA_FILE;
  *color = "\x1b[0m";
}

const char *lookup_dir_icon(const char *name) {
  for (auto &dt : dir_types) {
    if (strcasecmp(name, dt.name) == 0) return dt.icon;
  }
  return NF_FA_FOLDER;
}

//------------------------------------------
//  Entry storage for sorting
//------------------------------------------
struct Entry {
  char name[64];
  bool is_dir;
};

constexpr size_t MAX_ENTRIES = 128;

} // namespace

extern char g_cwd[];

//------------------------------------------
//  ls command
//------------------------------------------
int programs::coreutils::cmd_ls(int argc, char **argv) {
  char target[128];

  if (argc >= 2) {
    if (argv[1][0] == '/')
      strlcpy(target, argv[1], sizeof(target));
    else {
      strlcpy(target, g_cwd, sizeof(target));
      console::path::apply_cd(target, sizeof(target), argv[1]);
    }
  } else {
    strlcpy(target, g_cwd, sizeof(target));
  }

  File dir = SD.open(target);
  if (!dir || !dir.isDirectory()) {
    printf("ls: %s: not a directory\n", target);
    return 1;
  }

  static Entry entries[MAX_ENTRIES];
  size_t dir_count = 0;
  size_t file_count = 0;
  size_t max_name_len = 0;

  // Collect entries — directories first, then files
  File entry = dir.openNextFile();
  while (entry && (dir_count + file_count) < MAX_ENTRIES) {
    const char *name = entry.name();
    // SD library returns full path — extract just the filename
    const char *slash = strrchr(name, '/');
    if (slash) name = slash + 1;
    if (name[0] == '\0') { entry = dir.openNextFile(); continue; }

    size_t nlen = strlen(name);
    if (nlen >= sizeof(entries[0].name)) nlen = sizeof(entries[0].name) - 1;

    if (entry.isDirectory()) {
      // Insert at dir_count position (before files)
      if (dir_count + file_count > 0 && dir_count < dir_count + file_count) {
        memmove(&entries[dir_count + 1], &entries[dir_count],
                file_count * sizeof(Entry));
      }
      memcpy(entries[dir_count].name, name, nlen);
      entries[dir_count].name[nlen] = '\0';
      entries[dir_count].is_dir = true;
      dir_count++;
    } else {
      size_t idx = dir_count + file_count;
      memcpy(entries[idx].name, name, nlen);
      entries[idx].name[nlen] = '\0';
      entries[idx].is_dir = false;
      file_count++;
    }

    if (nlen > max_name_len) max_name_len = nlen;
    entry = dir.openNextFile();
  }
  dir.close();

  size_t total = dir_count + file_count;
  if (total == 0) {
    printf("\x1b[2m(empty)\x1b[0m\n");
    return 0;
  }

  // Calculate column layout
  size_t col_width = max_name_len + 4; // icon(2) + space(1) + name + padding
  uint16_t term_width = console::prompt::terminal_width();
  size_t num_cols = (term_width / col_width);
  if (num_cols < 1) num_cols = 1;
  size_t num_rows = (total + num_cols - 1) / num_cols;

  printf("\n");
  for (size_t row = 0; row < num_rows; row++) {
    for (size_t col = 0; col < num_cols; col++) {
      size_t idx = col * num_rows + row;
      if (idx >= total) continue;

      const Entry &e = entries[idx];
      size_t nlen = strlen(e.name);

      if (e.is_dir) {
        const char *icon = lookup_dir_icon(e.name);
        printf("  %s%s %s/\x1b[0m", DIR_COLOR, icon, e.name);
        size_t vis = 2 + 2 + 1 + nlen + 1;
        if (col < num_cols - 1) {
          for (size_t p = vis; p < col_width + 2; p++) printf(" ");
        }
      } else {
        const char *icon, *color;
        lookup_file(e.name, &icon, &color);
        printf("  %s%s %s\x1b[0m", color, icon, e.name);
        size_t vis = 2 + 2 + 1 + nlen;
        if (col < num_cols - 1) {
          for (size_t p = vis; p < col_width + 2; p++) printf(" ");
        }
      }
    }
    printf("\n");
  }
  printf("\n");
  return 0;
}
