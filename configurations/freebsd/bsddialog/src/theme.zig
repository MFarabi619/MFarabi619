const c = @import("c/bindings.zig").c;

fn color(fg: c.enum_bsddialog_color, bg: c.enum_bsddialog_color, flags: c_uint) c_int {
    return c.bsddialog_color(fg, bg, flags);
}

pub fn apply() !void {
    var theme: c.struct_bsddialog_theme = undefined;
    if (c.bsddialog_get_theme(&theme) != c.BSDDIALOG_OK) {
        return error.BSDDialogGetThemeFailed;
    }

    theme.screen.color = color(c.BSDDIALOG_BLACK, c.BSDDIALOG_RED, 0);

    theme.shadow.color = color(c.BSDDIALOG_BLACK, c.BSDDIALOG_BLACK, 0);
    theme.shadow.y = 1;
    theme.shadow.x = 2;

    theme.dialog.color = color(c.BSDDIALOG_WHITE, c.BSDDIALOG_BLACK, 0);
    theme.dialog.delimtitle = true;
    theme.dialog.titlecolor = color(c.BSDDIALOG_RED, c.BSDDIALOG_BLACK, 0);
    theme.dialog.bottomtitlecolor = color(c.BSDDIALOG_WHITE, c.BSDDIALOG_BLACK, 0);
    theme.dialog.lineraisecolor = color(c.BSDDIALOG_RED, c.BSDDIALOG_BLACK, 0);
    theme.dialog.linelowercolor = color(c.BSDDIALOG_RED, c.BSDDIALOG_BLACK, 0);
    theme.dialog.arrowcolor = color(c.BSDDIALOG_BLACK, c.BSDDIALOG_RED, 0);

    theme.menu.f_selectorcolor = color(c.BSDDIALOG_BLACK, c.BSDDIALOG_RED, c.BSDDIALOG_BOLD);
    theme.menu.selectorcolor = color(c.BSDDIALOG_WHITE, c.BSDDIALOG_BLACK, 0);

    theme.menu.f_prefixcolor = color(c.BSDDIALOG_BLACK, c.BSDDIALOG_BLACK, 0);
    theme.menu.prefixcolor = color(c.BSDDIALOG_BLACK, c.BSDDIALOG_BLACK, 0);

    theme.menu.f_namecolor = color(c.BSDDIALOG_BLACK, c.BSDDIALOG_RED, c.BSDDIALOG_BOLD);
    theme.menu.namecolor = color(c.BSDDIALOG_WHITE, c.BSDDIALOG_BLACK, 0);

    theme.menu.f_desccolor = color(c.BSDDIALOG_BLACK, c.BSDDIALOG_RED, c.BSDDIALOG_BOLD);
    theme.menu.desccolor = color(c.BSDDIALOG_WHITE, c.BSDDIALOG_BLACK, 0);

    theme.menu.f_shortcutcolor = color(c.BSDDIALOG_BLACK, c.BSDDIALOG_RED, c.BSDDIALOG_BOLD);
    theme.menu.shortcutcolor = color(c.BSDDIALOG_WHITE, c.BSDDIALOG_BLACK, 0);

    theme.menu.bottomdesccolor = color(c.BSDDIALOG_BLACK, c.BSDDIALOG_RED, 0);
    theme.menu.sepnamecolor = color(c.BSDDIALOG_RED, c.BSDDIALOG_BLACK, c.BSDDIALOG_BOLD);
    theme.menu.sepdesccolor = color(c.BSDDIALOG_WHITE, c.BSDDIALOG_BLACK, 0);

    theme.form.f_fieldcolor = color(c.BSDDIALOG_WHITE, c.BSDDIALOG_RED, c.BSDDIALOG_BOLD);
    theme.form.fieldcolor = color(c.BSDDIALOG_WHITE, c.BSDDIALOG_RED, c.BSDDIALOG_BOLD);
    theme.form.readonlycolor = color(c.BSDDIALOG_RED, c.BSDDIALOG_WHITE, c.BSDDIALOG_BOLD);
    theme.form.bottomdesccolor = color(c.BSDDIALOG_WHITE, c.BSDDIALOG_RED, 0);

    theme.bar.f_color = color(c.BSDDIALOG_WHITE, c.BSDDIALOG_RED, c.BSDDIALOG_BOLD);
    theme.bar.color = color(c.BSDDIALOG_RED, c.BSDDIALOG_WHITE, c.BSDDIALOG_BOLD);

    theme.button.minmargin = 1;
    theme.button.maxmargin = 5;
    theme.button.leftdelim = '[';
    theme.button.rightdelim = ']';
    theme.button.f_delimcolor = color(c.BSDDIALOG_BLACK, c.BSDDIALOG_RED, 0);
    theme.button.delimcolor = color(c.BSDDIALOG_WHITE, c.BSDDIALOG_BLACK, 0);
    theme.button.f_color = color(c.BSDDIALOG_BLACK, c.BSDDIALOG_RED, 0);
    theme.button.color = color(c.BSDDIALOG_WHITE, c.BSDDIALOG_BLACK, 0);
    theme.button.f_shortcutcolor = color(c.BSDDIALOG_BLACK, c.BSDDIALOG_RED, 0);
    theme.button.shortcutcolor = color(c.BSDDIALOG_WHITE, c.BSDDIALOG_BLACK, 0);

    if (c.bsddialog_set_theme(&theme) != c.BSDDIALOG_OK) {
        return error.BSDDialogSetThemeFailed;
    }
}

pub fn apply_orangey_black() !void {
    if (c.bsddialog_set_default_theme(c.BSDDIALOG_THEME_BLACKWHITE) != c.BSDDIALOG_OK) {
        return error.BSDDialogSetThemeFailed;
    }

    var theme: c.struct_bsddialog_theme = undefined;
    if (c.bsddialog_get_theme(&theme) != c.BSDDIALOG_OK) {
        return error.BSDDialogGetThemeFailed;
    }

    theme.screen.color = color(c.BSDDIALOG_YELLOW, c.BSDDIALOG_BLACK, 0);

    theme.shadow.color = color(c.BSDDIALOG_BLACK, c.BSDDIALOG_BLACK, 0);
    theme.shadow.y = 1;
    theme.shadow.x = 2;

    theme.dialog.color = color(c.BSDDIALOG_YELLOW, c.BSDDIALOG_BLACK, 0);
    theme.dialog.delimtitle = true;
    theme.dialog.titlecolor = color(c.BSDDIALOG_YELLOW, c.BSDDIALOG_BLACK, c.BSDDIALOG_BOLD);
    theme.dialog.bottomtitlecolor = color(c.BSDDIALOG_YELLOW, c.BSDDIALOG_BLACK, 0);
    theme.dialog.lineraisecolor = color(c.BSDDIALOG_YELLOW, c.BSDDIALOG_BLACK, 0);
    theme.dialog.linelowercolor = color(c.BSDDIALOG_YELLOW, c.BSDDIALOG_BLACK, 0);
    theme.dialog.arrowcolor = color(c.BSDDIALOG_BLACK, c.BSDDIALOG_YELLOW, 0);

    theme.menu.f_selectorcolor = color(c.BSDDIALOG_BLACK, c.BSDDIALOG_YELLOW, c.BSDDIALOG_BOLD);
    theme.menu.selectorcolor = color(c.BSDDIALOG_YELLOW, c.BSDDIALOG_BLACK, 0);

    theme.menu.f_prefixcolor = color(c.BSDDIALOG_BLACK, c.BSDDIALOG_YELLOW, c.BSDDIALOG_BOLD);
    theme.menu.prefixcolor = color(c.BSDDIALOG_YELLOW, c.BSDDIALOG_BLACK, 0);

    theme.menu.f_namecolor = color(c.BSDDIALOG_BLACK, c.BSDDIALOG_YELLOW, c.BSDDIALOG_BOLD);
    theme.menu.namecolor = color(c.BSDDIALOG_YELLOW, c.BSDDIALOG_BLACK, 0);

    theme.menu.f_desccolor = color(c.BSDDIALOG_BLACK, c.BSDDIALOG_YELLOW, c.BSDDIALOG_BOLD);
    theme.menu.desccolor = color(c.BSDDIALOG_YELLOW, c.BSDDIALOG_BLACK, 0);

    theme.menu.f_shortcutcolor = color(c.BSDDIALOG_BLACK, c.BSDDIALOG_YELLOW, c.BSDDIALOG_BOLD);
    theme.menu.shortcutcolor = color(c.BSDDIALOG_YELLOW, c.BSDDIALOG_BLACK, 0);

    theme.menu.bottomdesccolor = color(c.BSDDIALOG_YELLOW, c.BSDDIALOG_BLACK, 0);
    theme.menu.sepnamecolor = color(c.BSDDIALOG_YELLOW, c.BSDDIALOG_BLACK, c.BSDDIALOG_BOLD);
    theme.menu.sepdesccolor = color(c.BSDDIALOG_YELLOW, c.BSDDIALOG_BLACK, 0);

    theme.form.f_fieldcolor = color(c.BSDDIALOG_BLACK, c.BSDDIALOG_YELLOW, c.BSDDIALOG_BOLD);
    theme.form.fieldcolor = color(c.BSDDIALOG_YELLOW, c.BSDDIALOG_BLACK, 0);
    theme.form.readonlycolor = color(c.BSDDIALOG_YELLOW, c.BSDDIALOG_BLACK, c.BSDDIALOG_BOLD);
    theme.form.bottomdesccolor = color(c.BSDDIALOG_YELLOW, c.BSDDIALOG_BLACK, 0);

    theme.bar.f_color = color(c.BSDDIALOG_BLACK, c.BSDDIALOG_YELLOW, c.BSDDIALOG_BOLD);
    theme.bar.color = color(c.BSDDIALOG_YELLOW, c.BSDDIALOG_BLACK, 0);

    theme.button.minmargin = 1;
    theme.button.maxmargin = 5;
    theme.button.leftdelim = '[';
    theme.button.rightdelim = ']';
    theme.button.f_delimcolor = color(c.BSDDIALOG_BLACK, c.BSDDIALOG_YELLOW, c.BSDDIALOG_BOLD);
    theme.button.delimcolor = color(c.BSDDIALOG_YELLOW, c.BSDDIALOG_BLACK, 0);
    theme.button.f_color = color(c.BSDDIALOG_BLACK, c.BSDDIALOG_YELLOW, c.BSDDIALOG_BOLD);
    theme.button.color = color(c.BSDDIALOG_YELLOW, c.BSDDIALOG_BLACK, 0);
    theme.button.f_shortcutcolor = color(c.BSDDIALOG_BLACK, c.BSDDIALOG_YELLOW, c.BSDDIALOG_BOLD);
    theme.button.shortcutcolor = color(c.BSDDIALOG_YELLOW, c.BSDDIALOG_BLACK, 0);

    if (c.bsddialog_set_theme(&theme) != c.BSDDIALOG_OK) {
        return error.BSDDialogSetThemeFailed;
    }
}

pub fn apply_black_white() !void {
    if (c.bsddialog_set_default_theme(c.BSDDIALOG_THEME_BLACKWHITE) != c.BSDDIALOG_OK) {
        return error.BSDDialogSetThemeFailed;
    }
}
