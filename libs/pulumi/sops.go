package main

import (
	"path/filepath"

	sopsconfig "github.com/getsops/sops/v3/config"
	"github.com/getsops/sops/v3/decrypt"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"gopkg.in/yaml.v3"
)

func decryptSecret(key string) (pulumi.Output, error) {
	sopsFile, err := sopsconfig.FindConfigFile(".")
	if err != nil {
		return nil, err
	}

	cleartext, err := decrypt.File(filepath.Join(filepath.Dir(sopsFile), "secrets.yaml"), "yaml")
	if err != nil {
		return nil, err
	}

	var secrets map[string]string
	if err := yaml.Unmarshal(cleartext, &secrets); err != nil {
		return nil, err
	}

	return pulumi.ToSecret(pulumi.String(secrets[key])), nil
}
