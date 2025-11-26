package providers

import (
	"fmt"
	"github.com/pulumi/pulumi-aws/sdk/v7/go/aws/s3"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

type AwsS3Website struct {
	pulumi.ResourceState
	Url pulumi.StringOutput
}

type AwsS3WebsiteArgs struct {
	Files []string
}

func NewAwsS3Website(ctx *pulumi.Context, name string, args AwsS3WebsiteArgs, opts ...pulumi.ResourceOption) (*AwsS3Website, error) {
	self := &AwsS3Website{}
	err := ctx.RegisterComponentResource("quickstart:index:AwsS3Website", name, self, opts...)
	if err != nil {
		return nil, err
	}

	bucket, err := s3.NewBucket(ctx, "my-bucket", nil,
		pulumi.Parent(self))

	if err != nil {
		return nil, err
	}

	website, err := s3.NewBucketWebsiteConfiguration(ctx, "website", &s3.BucketWebsiteConfigurationArgs{
		Bucket: bucket.ID(),
		IndexDocument: &s3.BucketWebsiteConfigurationIndexDocumentArgs{
			Suffix: pulumi.String("index.html"),
		},
	}, pulumi.Parent(self))

	if err != nil {
		return nil, err
	}

	ownershipControls, err := s3.NewBucketOwnershipControls(ctx, "ownership-controls", &s3.BucketOwnershipControlsArgs{
		Bucket: bucket.ID(),
		Rule: &s3.BucketOwnershipControlsRuleArgs{
			ObjectOwnership: pulumi.String("ObjectWriter"),
		},
	}, pulumi.Parent(self))

	if err != nil {
		return nil, err
	}

	publicAccessBlock, err := s3.NewBucketPublicAccessBlock(ctx, "public-access-block", &s3.BucketPublicAccessBlockArgs{
		Bucket:          bucket.ID(),
		BlockPublicAcls: pulumi.Bool(false),
	}, pulumi.Parent(self))

	if err != nil {
		return nil, err
	}

	for _, file := range args.Files {
		_, err = s3.NewBucketObject(ctx, file, &s3.BucketObjectArgs{
			Bucket:      bucket.ID(),
			Source:      pulumi.NewFileAsset(file),
			ContentType: pulumi.String("text/html"),
			Acl:         pulumi.String("public-read"),
		}, pulumi.DependsOn([]pulumi.Resource{ownershipControls, publicAccessBlock}),
			pulumi.Parent(self))
	}

	if err != nil {
		return nil, err
	}

	self.Url = website.WebsiteEndpoint.ApplyT(func(websiteEndpoint string) (string, error) {
		return fmt.Sprintf("http://%v", websiteEndpoint), nil
	}).(pulumi.StringOutput)

	ctx.RegisterResourceOutputs(website, pulumi.Map{"url": self.Url})
	return self, nil
}
