package s3

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"github.com/aws/aws-sdk-go-v2/aws"
	config2 "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"log"
	"os"
	"server/config"
	"time"
)

type S3Storage struct {
	Client   *s3.Client
	Endpoint string
	Region   string
	Buckets  []config.BucketConfig
}

func NewS3Storage(config config.S3Config) (*S3Storage, error) {
	accessKey := os.Getenv("S3_ACCESS_KEY")
	secretKey := os.Getenv("S3_SECRET_KEY")

	if accessKey == "" || secretKey == "" {
		return nil, errors.New("s3 environment variables are not set")
	}

	customResolver := aws.EndpointResolverFunc(func(service, region string) (aws.Endpoint, error) {
		if service == s3.ServiceID {
			return aws.Endpoint{
				URL: "https://" + config.Endpoint,
			}, nil
		}
		return aws.Endpoint{}, &aws.EndpointNotFoundError{}
	})

	cfg, err := config2.LoadDefaultConfig(context.Background(),
		config2.WithCredentialsProvider(credentials.NewStaticCredentialsProvider(accessKey, secretKey, "")),
		config2.WithRegion(config.Region),
		config2.WithEndpointResolver(customResolver),
	)
	if err != nil {
		return nil, err
	}

	client := s3.NewFromConfig(cfg)
	storage := &S3Storage{
		Client:   client,
		Endpoint: config.Endpoint,
		Region:   config.Region,
		Buckets:  config.Buckets,
	}

	// Создаем бакеты из конфигурации
	for _, bucket := range config.Buckets {
		err := storage.createBucketIfNotExists(bucket)
		if err != nil {
			return nil, fmt.Errorf("failed to initialize bucket %s: %v", bucket.Name, err)
		}
	}

	return storage, nil
}

func retryHeadBucket(client *s3.Client, bucket string, retries int, delay time.Duration) error {
	var err error
	for i := 0; i < retries; i++ {
		_, err = client.HeadBucket(context.TODO(), &s3.HeadBucketInput{
			Bucket: &bucket,
		})
		if err == nil {
			return nil
		}

		// Логируем ошибку и ожидаем перед следующей попыткой
		log.Printf("Attempt %d: Error checking bucket: %v", i+1, err)
		time.Sleep(delay)
	}
	return fmt.Errorf("failed to check bucket after %d attempts: %v", retries, err)
}

func (s *S3Storage) createBucketIfNotExists(bucket config.BucketConfig) error {
	err := retryHeadBucket(s.Client, bucket.Name, 2, 2*time.Second)
	if err != nil {
		log.Printf("Error checking bucket existence: %v", err)

		_, err := s.Client.CreateBucket(context.TODO(), &s3.CreateBucketInput{
			Bucket: &bucket.Name,
		})
		if err != nil {
			return fmt.Errorf("unable to create bucket: %v", err)
		}
		log.Printf("Bucket %s created successfully.", bucket.Name)

		err = applyBucketPolicy(s.Client, bucket.Name)
		if err != nil {
			return fmt.Errorf("failed to apply bucket policy: %v", err)
		}

		time.Sleep(10 * time.Second)

		err = uploadDefaultAvatar(s.Client, bucket)
		if err != nil {
			return fmt.Errorf("failed to upload default avatar: %v", err)
		}
	}
	return nil
}

func applyBucketPolicy(client *s3.Client, bucket string) error {
	policy := `{
		"Version": "2012-10-17",
		"Statement": [
			{
				"Effect": "Allow",
				"Action": ["s3:GetObject"],
				"Resource": "arn:aws:s3:::` + bucket + `/*",
				"Principal": "*"
			}
		]
	}`

	_, err := client.PutBucketPolicy(context.TODO(), &s3.PutBucketPolicyInput{
		Bucket: &bucket,
		Policy: &policy,
	})

	if err != nil {
		return fmt.Errorf("failed to apply bucket policy: %v", err)
	}

	log.Printf("Bucket policy applied to %s successfully.", bucket)
	return nil
}

func uploadDefaultAvatar(client *s3.Client, bucket config.BucketConfig) error {
	for i, path := range bucket.DefaultFile.Path {
		file, err := os.Open(path)
		if err != nil {
			return fmt.Errorf("unable to open default file %s: %v", path, err)
		}
		defer file.Close()

		fileData, err := os.ReadFile(path)
		if err != nil {
			return fmt.Errorf("failed to read default file %s: %v", path, err)
		}

		key := bucket.DefaultFile.Keys[i]
		uploadInput := &s3.PutObjectInput{
			Bucket:      &bucket.Name,
			Key:         aws.String(key),
			Body:        bytes.NewReader(fileData),
			ContentType: aws.String("image/webp"),
		}

		_, err = client.PutObject(context.TODO(), uploadInput)
		if err != nil {
			return fmt.Errorf("failed to upload %s to S3: %v", key, err)
		}
	}
	return nil
}
