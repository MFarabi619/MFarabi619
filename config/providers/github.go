package providers

import (
	"github.com/pulumi/pulumi-github/sdk/v6/go/github"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func SetupGitHub(ctx *pulumi.Context) error {
	_, err := github.NewUserGpgKey(ctx, "mfarabi619@gmail.com", &github.UserGpgKeyArgs{
		ArmoredPublicKey: pulumi.String("-----BEGIN PGP PUBLIC KEY BLOCK-----\n mDMEaR5MBRYJKwYBBAHaRw8BAQdAFcxnY9PEwt8tHa1IagKgLxx7fXFHSioJce3Y\n P+/+QmG0Jk11bXRhaGluIEZhcmFiaSA8bWZhcmFiaTYxOUBnbWFpbC5jb20+iI4E\n ExYKADYWIQTLy0CAKAv3hRizBHswa5TaLOYZigUCaR5MBQIbAwQLCQgHBBUKCQgF\n FgIDAQACHgECF4AACgkQMGuU2izmGYqn8QEAlDnuRUk2VmlZysNG6MEE7VvRITPO\n Frfc6TKQOg+2mckA/0bEhuH5DXy2U8JQMfUkrEQSZ4dcvsFAoTeWh0Rva7oEuDgE\n aR5MBRIKKwYBBAGXVQEFAQEHQI8x2tLx0SF5HqDe+dIlUOTynrHK1vyYTfPnEcaH\n TXpMAwEIB4h4BBgWCgAgFiEEy8tAgCgL94UYswR7MGuU2izmGYoFAmkeTAUCGwwA\n CgkQMGuU2izmGYpSTgEAnRv5MHdDyMPvz+uQocGxkach8vaibYASmZUcSCvBzWQA\n /2IBEfo3yFg98z07OkkmiU4/T2Wg+vUhPo6CLJbd3AYH\n =e+V4\n -----END PGP PUBLIC KEY BLOCK-----"),
	})
	if err != nil {
		return err
	}

	return nil
}
