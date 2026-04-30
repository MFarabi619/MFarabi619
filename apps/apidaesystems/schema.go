package main

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func resolveSchemaSQL() (string, error) {
	schemaPath := filepath.Join("..", "..", "learning", "sql", "src", "schema.sql")
	return resolveFile(schemaPath, make(map[string]string))
}

func resolveFile(filePath string, variables map[string]string) (string, error) {
	file, err := os.Open(filePath)
	if err != nil {
		return "", fmt.Errorf("opening %s: %w", filePath, err)
	}
	defer file.Close()

	dir := filepath.Dir(filePath)
	var result strings.Builder
	scanner := bufio.NewScanner(file)

	for scanner.Scan() {
		line := scanner.Text()
		trimmed := strings.TrimSpace(line)

		if isSkippableMetaCommand(trimmed) {
			continue
		}

		if trimmed == `\ir drop_schema.sql` {
			continue
		}

		if strings.HasPrefix(trimmed, `\set `) {
			parts := strings.SplitN(trimmed, " ", 3)
			if len(parts) == 3 {
				variables[parts[1]] = strings.Trim(parts[2], "'")
			}
			continue
		}

		if strings.HasPrefix(trimmed, `\ir `) {
			includePath := strings.TrimPrefix(trimmed, `\ir `)
			content, err := resolveFile(filepath.Join(dir, includePath), variables)
			if err != nil {
				return "", err
			}
			result.WriteString(content)
			continue
		}

		resolved := substituteVariables(line, variables)

		if strings.HasPrefix(trimmed, "CREATE EXTENSION IF NOT EXISTS") {
			extensionName := strings.TrimSuffix(strings.TrimPrefix(trimmed, "CREATE EXTENSION IF NOT EXISTS "), ";")
			result.WriteString("DO $ext$ BEGIN\n")
			result.WriteString("    " + strings.TrimSpace(resolved) + "\n")
			result.WriteString("EXCEPTION WHEN OTHERS THEN\n")
			result.WriteString(fmt.Sprintf("    RAISE NOTICE 'Extension %s not available: %%', SQLERRM;\n", strings.TrimSpace(extensionName)))
			result.WriteString("END $ext$;\n")
			continue
		}

		result.WriteString(resolved)
		result.WriteString("\n")
	}

	if err := scanner.Err(); err != nil {
		return "", fmt.Errorf("scanning %s: %w", filePath, err)
	}

	return result.String(), nil
}

func isSkippableMetaCommand(line string) bool {
	prefixes := []string{`\getenv`, `\if`, `\else`, `\endif`, `\quit`, `\cd`, `\echo`}
	for _, prefix := range prefixes {
		if strings.HasPrefix(line, prefix) {
			return true
		}
	}
	return false
}

func substituteVariables(line string, variables map[string]string) string {
	result := line
	for name, value := range variables {
		result = strings.ReplaceAll(result, ":'"+name+"'", "'"+value+"'")
	}
	return result
}
