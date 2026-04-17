#include <stdio.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define CLAY_IMPLEMENTATION
#include "clay.h"
#include "clay_renderer_terminal_ansi.c"

static void on_error(Clay_ErrorData error) {
  fprintf(stderr, "clay error: %.*s\n", error.errorText.length,
          error.errorText.chars);
}

int main(void) {
  struct winsize ws;
  ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws);
  int term_width  = ws.ws_col;
  int term_height = ws.ws_row;
  int col_width   = ws.ws_xpixel / ws.ws_col;
  if (col_width == 0) col_width = 8;

  uint32_t mem_size = Clay_MinMemorySize();
  Clay_Arena arena  = Clay_CreateArenaWithCapacityAndMemory(mem_size, malloc(mem_size));

  Clay_Initialize(arena,
                  (Clay_Dimensions){(float)(term_width * col_width),
                                    (float)(term_height * col_width)},
                  (Clay_ErrorHandler){.errorHandlerFunction = on_error});
  Clay_SetMeasureTextFunction(Console_MeasureText, &col_width);

  Clay_BeginLayout();

  CLAY(CLAY_ID("Root"), {
      .layout = {
          .sizing          = {CLAY_SIZING_GROW(0), CLAY_SIZING_GROW(0)},
          .layoutDirection = CLAY_TOP_TO_BOTTOM,
          .padding         = {1, 1, 1, 1},
          .childGap        = 1,
      },
      .backgroundColor = {30, 30, 30, 255},
  }) {
    CLAY(CLAY_ID("Header"), {
        .layout = {
            .sizing         = {CLAY_SIZING_GROW(0), CLAY_SIZING_FIXED(3 * col_width)},
            .padding        = {1, 1, 0, 0},
            .childAlignment = {.y = CLAY_ALIGN_Y_CENTER},
        },
        .backgroundColor = {50, 120, 200, 255},
    }) {
      CLAY_TEXT(CLAY_STRING("Hello, Clay!"), CLAY_TEXT_CONFIG({
          .textColor = {255, 255, 255, 255},
          .fontSize  = 1,
      }));
    }

    CLAY(CLAY_ID("Body"), {
        .layout = {
            .sizing   = {CLAY_SIZING_GROW(0), CLAY_SIZING_GROW(0)},
            .childGap = 1,
        },
    }) {
      CLAY(CLAY_ID("Sidebar"), {
          .layout = {
              .sizing          = {CLAY_SIZING_FIXED(20 * col_width), CLAY_SIZING_GROW(0)},
              .padding         = {1, 1, 1, 1},
              .layoutDirection = CLAY_TOP_TO_BOTTOM,
              .childGap        = 1,
          },
          .backgroundColor = {45, 45, 45, 255},
      }) {
        CLAY_TEXT(CLAY_STRING("Sidebar"), CLAY_TEXT_CONFIG({
            .textColor = {180, 180, 180, 255},
            .fontSize  = 1,
        }));
        CLAY_TEXT(CLAY_STRING("Item 1"), CLAY_TEXT_CONFIG({
            .textColor = {140, 140, 140, 255},
            .fontSize  = 1,
        }));
        CLAY_TEXT(CLAY_STRING("Item 2"), CLAY_TEXT_CONFIG({
            .textColor = {140, 140, 140, 255},
            .fontSize  = 1,
        }));
        CLAY_TEXT(CLAY_STRING("Item 3"), CLAY_TEXT_CONFIG({
            .textColor = {140, 140, 140, 255},
            .fontSize  = 1,
        }));
      }

      CLAY(CLAY_ID("Content"), {
          .layout = {
              .sizing          = {CLAY_SIZING_GROW(0), CLAY_SIZING_GROW(0)},
              .padding         = {2, 2, 1, 1},
              .layoutDirection = CLAY_TOP_TO_BOTTOM,
              .childGap        = 1,
          },
          .backgroundColor = {40, 40, 40, 255},
      }) {
        CLAY_TEXT(CLAY_STRING("Welcome to Clay."), CLAY_TEXT_CONFIG({
            .textColor = {220, 220, 220, 255},
            .fontSize  = 1,
        }));
        CLAY_TEXT(CLAY_STRING("A declarative UI layout library in a single C header."), CLAY_TEXT_CONFIG({
            .textColor = {160, 160, 160, 255},
            .fontSize  = 1,
        }));
        CLAY_TEXT(CLAY_STRING("This is rendering in your terminal via ANSI escape codes."), CLAY_TEXT_CONFIG({
            .textColor = {100, 180, 100, 255},
            .fontSize  = 1,
        }));
      }
    }
  }

  Clay_RenderCommandArray commands = Clay_EndLayout(0.016f);
  Clay_Terminal_Render(commands, term_width, term_height, col_width);

  printf("\033[%d;1H", term_height);

  free(arena.memory);
  return 0;
}
