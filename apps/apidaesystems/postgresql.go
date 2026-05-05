package main

import (
	"github.com/pulumi/pulumi-command/sdk/go/command/local"
	"github.com/pulumi/pulumi-docker/sdk/v5/go/docker"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func authentikInitScript(secrets map[string]string) string {
	return "#!/bin/bash\nset -e\npsql -v ON_ERROR_STOP=1 --username \"$POSTGRES_USER\" <<-EOSQL\n" +
		"    SELECT 'CREATE USER authentik WITH PASSWORD ''" + secrets["AUTHENTIK_PG_PASSWORD"] + "''' WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authentik')\\gexec\n" +
		"    SELECT 'CREATE DATABASE authentik OWNER authentik' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'authentik')\\gexec\n" +
		"EOSQL\n"
}

func grafanaInitScript() string {
	return "#!/bin/bash\nset -e\n" +
		"psql -v ON_ERROR_STOP=1 --username \"$POSTGRES_USER\" <<-EOSQL\n" +
		"    SELECT 'CREATE USER grafana WITH LOGIN' WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'grafana')\\gexec\n" +
		"    SELECT 'CREATE DATABASE grafana OWNER grafana' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'grafana')\\gexec\n" +
		"EOSQL\n" +
		"sed -i '/^host.*all.*all.*all/i host    grafana     grafana     all             trust' \"$PGDATA/pg_hba.conf\"\n"
}

// grafanaGrantsScript runs after the apidae and ceratina schemas have been
// loaded, granting the read-only `grafana` role SELECT on the existing tables
// and ALTER DEFAULT PRIVILEGES so future tables created by `apidae` are
// readable too. Without this, trust auth in pg_hba.conf gets `grafana` into
// the database but every query fails with "permission denied".
func grafanaGrantsScript() string {
	return "#!/bin/bash\nset -e\n" +
		"for db in apidae ceratina; do\n" +
		"  psql -v ON_ERROR_STOP=1 --username \"$POSTGRES_USER\" --dbname \"$db\" <<-EOSQL\n" +
		"    GRANT USAGE ON SCHEMA public TO grafana;\n" +
		"    GRANT SELECT ON ALL TABLES IN SCHEMA public TO grafana;\n" +
		"    ALTER DEFAULT PRIVILEGES FOR ROLE apidae IN SCHEMA public GRANT SELECT ON TABLES TO grafana;\n" +
		"EOSQL\n" +
		"done\n"
}

// apidaeInitScript creates the dedicated `apidae` database that holds the
// sensor schema (events, samples, metrics) and the pgnats subscription. The
// pg_hba.conf trust line lets the `grafana` role read it for dashboards;
// PUBLIC's default CONNECT privilege covers catalog-level access.
func apidaeInitScript() string {
	return "#!/bin/bash\nset -e\n" +
		"psql -v ON_ERROR_STOP=1 --username \"$POSTGRES_USER\" <<-EOSQL\n" +
		"    SELECT 'CREATE USER apidae WITH LOGIN' WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'apidae')\\gexec\n" +
		"    SELECT 'CREATE DATABASE apidae OWNER apidae' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'apidae')\\gexec\n" +
		"EOSQL\n" +
		"sed -i '/^host.*all.*all.*all/i host    apidae      grafana     all             trust' \"$PGDATA/pg_hba.conf\"\n"
}

// ceratinaInitScript creates the `ceratina` database that ingests data from
// the legacy C++/Arduino firmware (apps/ceratina) via http_get + pg_cron. It
// is owned by the `apidae` role created in apidaeInitScript() so we don't
// need a separate user. Trust auth lets the `grafana` role read it for
// horizon's dashboards, mirroring the apidae pattern.
func ceratinaInitScript() string {
	return "#!/bin/bash\nset -e\n" +
		"psql -v ON_ERROR_STOP=1 --username \"$POSTGRES_USER\" <<-EOSQL\n" +
		"    SELECT 'CREATE DATABASE ceratina OWNER apidae' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'ceratina')\\gexec\n" +
		"EOSQL\n" +
		"sed -i '/^host.*all.*all.*all/i host    ceratina    grafana     all             trust' \"$PGDATA/pg_hba.conf\"\n"
}

func createPostgreSQL(ctx *pulumi.Context, proxyNetwork *docker.Network, secrets map[string]string, settings serviceConfig, initScripts docker.ContainerUploadArray, dependsOn ...pulumi.Resource) (*docker.Container, error) {
	data, err := createVolume(ctx, "postgresql-data")
	if err != nil {
		return nil, err
	}

	const imageTag = "apidae-systems-postgresql:latest"

	buildImage, err := local.NewCommand(ctx, "postgresql-image-build", &local.CommandArgs{
		Create: pulumi.String("docker build -t " + imageTag + " ./docker/postgresql/"),
		Delete: pulumi.Sprintf("docker rmi %s || true", imageTag),
	})
	if err != nil {
		return nil, err
	}

	var containerOptions []pulumi.ResourceOption
	containerOptions = append(containerOptions, pulumi.AdditionalSecretOutputs([]string{"envs"}))
	dependsOn = append(dependsOn, buildImage)
	containerOptions = append(containerOptions, pulumi.DependsOn(dependsOn))

	container, err := docker.NewContainer(ctx, "postgresql", &docker.ContainerArgs{
		Image:               pulumi.String(imageTag),
		Name:                pulumi.String("postgresql"),
		Hostname:            pulumi.String("postgresql"),
		Restart:             pulumi.String("unless-stopped"),
		Wait:                pulumi.Bool(true),
		WaitTimeout:         pulumi.Int(120),
		Memory:              pulumi.Int(settings.Memory),
		MemorySwap:          pulumi.Int(settings.Memory),
		MemoryReservation:   pulumi.Int(settings.Memory * 3 / 4),
		CpuShares:           pulumi.Int(1024),
		ShmSize:             pulumi.Int(256),
		StopTimeout:         pulumi.Int(30),
		DestroyGraceSeconds: pulumi.Int(30),
		Command: pulumi.StringArray{
			pulumi.String("postgres"),
			pulumi.String("-c"),
			pulumi.String("shared_preload_libraries=timescaledb,pgnats,pg_cron"),
			pulumi.String("-c"),
			pulumi.String("cron.database_name=ceratina"),
		},
		Ports: docker.ContainerPortArray{
			&docker.ContainerPortArgs{
				Internal: pulumi.Int(5432),
				External: pulumi.Int(5432),
			},
		},
		Capabilities: &docker.ContainerCapabilitiesArgs{
			Drops: pulumi.StringArray{pulumi.String("ALL")},
			Adds: pulumi.StringArray{
				pulumi.String("CHOWN"),
				pulumi.String("SETUID"),
				pulumi.String("SETGID"),
				pulumi.String("DAC_OVERRIDE"),
				pulumi.String("FOWNER"),
			},
		},
		LogDriver: pulumi.String("json-file"),
		LogOpts: pulumi.StringMap{
			"max-size": pulumi.String("10m"),
			"max-file": pulumi.String("3"),
		},
		Envs: pulumi.StringArray{
			pulumi.String("POSTGRES_DB=postgres"),
			pulumi.String("POSTGRES_USER=postgres"),
			pulumi.String("POSTGRES_PASSWORD=" + secrets["PG_SUPERUSER_PASSWORD"]),
			pulumi.String("TIMESCALEDB_TELEMETRY=off"),
		},
		Uploads: initScripts,
		Volumes: docker.ContainerVolumeArray{
			&docker.ContainerVolumeArgs{
				VolumeName:    data.Name,
				ContainerPath: pulumi.String("/home/postgres/pgdata"),
			},
		},
		Healthcheck: &docker.ContainerHealthcheckArgs{
			Tests: pulumi.StringArray{
				pulumi.String("CMD-SHELL"),
				pulumi.String("pg_isready -U postgres -d postgres"),
			},
			Interval:    pulumi.String("30s"),
			Timeout:     pulumi.String("10s"),
			Retries:     pulumi.Int(5),
			StartPeriod: pulumi.String("20s"),
		},
		NetworksAdvanced: docker.ContainerNetworksAdvancedArray{
			&docker.ContainerNetworksAdvancedArgs{
				Name: proxyNetwork.Name,
			},
		},
	}, containerOptions...)
	if err != nil {
		return nil, err
	}

	ctx.Export("postgresql id", container.ID())
	ctx.Export("postgresql data", data.Mountpoint)

	return container, nil
}
