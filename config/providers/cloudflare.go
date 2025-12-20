package providers

import (
	"github.com/pulumi/pulumi-cloudflare/sdk/v6/go/cloudflare"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

type DNSRecord struct {
	ZoneID  string
	Name    string
	Type    string
	Content string
	Ttl     float64
	Proxied bool
}

func SetupCloudflare(ctx *pulumi.Context) error {
	records := []DNSRecord{
		{
			ZoneID:  "d731987d8d7783e4b7cacb1f2025d7c2",
			Name:    "openws.org",
			Type:    "CNAME",
			Content: "dc81f04d-07df-4704-abac-07ffabdc173c.cfargotunnel.com",
			Ttl:     1,
			Proxied: true,
		},
		{
			ZoneID:  "d731987d8d7783e4b7cacb1f2025d7c2",
			Name:    "www.openws.org",
			Type:    "CNAME",
			Content: "dc81f04d-07df-4704-abac-07ffabdc173c.cfargotunnel.com",
			Ttl:     1,
			Proxied: true,
		},
		{
			ZoneID:  "d731987d8d7783e4b7cacb1f2025d7c2",
			Name:    "*.openws.org",
			Type:    "CNAME",
			Content: "dc81f04d-07df-4704-abac-07ffabdc173c.cfargotunnel.com",
			Ttl:     1,
			Proxied: true,
		},
		{
			ZoneID:  "dfdefc5dd51b109553bd178b7cc29eeb",
			Name:    "microvisor.systems",
			Type:    "CNAME",
			Content: "dc81f04d-07df-4704-abac-07ffabdc173c.cfargotunnel.com",
			Ttl:     1,
			Proxied: true,
		},
		{
			ZoneID:  "dfdefc5dd51b109553bd178b7cc29eeb",
			Name:    "www.microvisor.systems",
			Type:    "CNAME",
			Content: "dc81f04d-07df-4704-abac-07ffabdc173c.cfargotunnel.com",
			Ttl:     1,
			Proxied: true,
		},
		{
			ZoneID:  "dfdefc5dd51b109553bd178b7cc29eeb",
			Name:    "*.microvisor.systems",
			Type:    "CNAME",
          Content: "dc81f04d-07df-4704-abac-07ffabdc173c.cfargotunnel.com",
          Ttl:     1,
          Proxied: true,
        },
        {
          ZoneID:  "fcbb04c6968bf282f1fc97a51e7b5567",
          Name:    "microvisor.dev",
          Type:    "CNAME",
          Content: "dc81f04d-07df-4704-abac-07ffabdc173c.cfargotunnel.com",
          Ttl:     1,
          Proxied: true,
        },
        {
          ZoneID:  "fcbb04c6968bf282f1fc97a51e7b5567",
          Name:    "www.microvisor.dev",
          Type:    "CNAME",
          Content: "dc81f04d-07df-4704-abac-07ffabdc173c.cfargotunnel.com",
          Ttl:     1,
          Proxied: true,
        },
        {
          ZoneID:  "fcbb04c6968bf282f1fc97a51e7b5567",
          Name:    "*.microvisor.dev",
          Type:    "CNAME",
          Content: "dc81f04d-07df-4704-abac-07ffabdc173c.cfargotunnel.com",
          Ttl:     1,
          Proxied: true,
        },
        {
          ZoneID:  "9f2ca59c7037b40a1747cebf23ba6254",
          Name:    "mfarabi.dev",
          Type:    "A",
          Content: "66.33.60.130",
          Ttl:     1,
          Proxied: true,
        },
        {
          ZoneID:  "2f942a3403acf78759097b7e6979886f",
          Name:    "tandemrobotics.ca",
          Type:    "CNAME",
          Content: "dc81f04d-07df-4704-abac-07ffabdc173c.cfargotunnel.com",
          Ttl:     1,
          Proxied: true,
        },
        {
          ZoneID:  "2f942a3403acf78759097b7e6979886f",
          Name:    "www.tandemrobotics.ca",
          Type:    "CNAME",
          Content: "dc81f04d-07df-4704-abac-07ffabdc173c.cfargotunnel.com",
          Ttl:     1,
          Proxied: true,
        },
        {
          ZoneID:  "2f942a3403acf78759097b7e6979886f",
          Name:    "*.tandemrobotics.ca",
          Type:    "CNAME",
          Content: "dc81f04d-07df-4704-abac-07ffabdc173c.cfargotunnel.com",
          Ttl:     1,
          Proxied: true,
        },
        {
          ZoneID:  "c0fbb804f9ab75929039df08ce07c9d5",
          Name:    "apidaesystems.ca",
          Type:    "CNAME",
          Content: "dc81f04d-07df-4704-abac-07ffabdc173c.cfargotunnel.com",
          Ttl:     1,
          Proxied: true,
        },
        {
          ZoneID:  "c0fbb804f9ab75929039df08ce07c9d5",
          Name:    "www.apidaesystems.ca",
          Type:    "CNAME",
          Content: "ghs.googlehosted.com",
          Ttl:     1,
          Proxied: false,
        },
        {
          ZoneID:  "c0fbb804f9ab75929039df08ce07c9d5",
          Name:    "*.apidaesystems.ca",
          Type:    "CNAME",
          Content: "dc81f04d-07df-4704-abac-07ffabdc173c.cfargotunnel.com",
          Ttl:     1,
          Proxied: true,
        },
        {
          ZoneID:  "d1643aa85dae27953a0855781fbfb97e",
          Name:    "doombsd.org",
          Type:    "A",
          Content: "159.89.121.190",
          Ttl:     60,
          Proxied: false,
        },
        {
          ZoneID:  "d1643aa85dae27953a0855781fbfb97e",
          Name:    "www.doombsd.org",
          Type:    "A",
          Content: "159.89.121.190",
          Ttl:     60,
          Proxied: false,
        },
        {
          ZoneID:  "a50e95e1710564aa7890579946b311fb",
          Name:    "archunix.org",
          Type:    "A",
          Content: "159.89.121.190",
          Ttl:     60,
          Proxied: false,
        },
        {
          ZoneID:  "a50e95e1710564aa7890579946b311fb",
          Name:    "www.archunix.org",
          Type:    "A",
          Content: "159.89.121.190",
          Ttl:     60,
          Proxied: false,
        },
      }

	for _, record := range records {
		_, err := cloudflare.NewDnsRecord(ctx, record.Name, &cloudflare.DnsRecordArgs{
			ZoneId:  pulumi.String(record.ZoneID),
			Name:    pulumi.String(record.Name),
			Type:    pulumi.String(record.Type),
			Comment: pulumi.String("DO NOT TOUCH - PROVISIONED BY PULUMI"),
			Content: pulumi.String(record.Content),
			Ttl:     pulumi.Float64(record.Ttl),
			Proxied: pulumi.Bool(record.Proxied),
		})

		if err != nil {
			return err
		}
	}

	return nil
}
