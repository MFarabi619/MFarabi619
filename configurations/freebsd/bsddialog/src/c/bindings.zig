pub const c = @cImport({
    @cInclude("locale.h");
    @cInclude("bsddialog.h");
    @cInclude("bsddialog_theme.h");
});
