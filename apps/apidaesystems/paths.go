package main

import (
	"path/filepath"
	"runtime"
)

// monorepoRoot resolves to the repo root from this file's compile-time path,
// so callers don't depend on the process CWD.
func monorepoRoot() string {
	_, file, _, _ := runtime.Caller(0)
	return filepath.Clean(filepath.Join(filepath.Dir(file), "..", ".."))
}

func repoPath(parts ...string) string {
	return filepath.Join(append([]string{monorepoRoot()}, parts...)...)
}
