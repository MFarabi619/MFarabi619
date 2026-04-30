package main

import (
	_ "embed"
	"encoding/json"

	"gopkg.in/yaml.v3"
)

//go:embed dashboard-home.yaml
var homeDashboardYAML []byte

func buildHomeDashboardSpec() (string, error) {
	var envelope struct {
		Spec any `yaml:"spec"`
	}
	if err := yaml.Unmarshal(homeDashboardYAML, &envelope); err != nil {
		return "", err
	}
	specJSON, err := json.Marshal(envelope.Spec)
	if err != nil {
		return "", err
	}
	return string(specJSON), nil
}
