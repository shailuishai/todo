package s3

import (
	"context"
	"errors"
	"fmt"
	"github.com/aws/aws-sdk-go-v2/aws"
	awsConfig "github.com/aws/aws-sdk-go-v2/config" // Используем псевдоним
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types" // Для типов ошибок и конфигурации создания бакета
	"log"                                           // Стандартный log для этого пакета
	"os"
	"server/config" // Твоя структура конфигурации
	"strings"
	"time"
)

// S3Storage содержит клиент и конфигурацию S3.
type S3Storage struct {
	Client *s3.Client
	Cfg    config.S3Config
}

const (
	delayBeforeS3Init         = 1 * time.Second
	delayBetweenHeadAndCreate = 1 * time.Second
	delayAfterCreateOp        = 3 * time.Second
	delayAfterPolicyOp        = 2 * time.Second
	delayBetweenBucketOps     = 5 * time.Second
)

// NewS3Storage инициализирует S3 клиент, проверяет/создает бакеты и применяет политики.
func NewS3Storage(appS3Cfg config.S3Config) (*S3Storage, error) {
	accessKey := os.Getenv("S3_ACCESS_KEY")
	secretKey := os.Getenv("S3_SECRET_KEY")

	if accessKey == "" || secretKey == "" {
		return nil, errors.New("S3_ACCESS_KEY or S3_SECRET_KEY environment variables are not set")
	}

	log.Printf("S3 Init: Starting S3 client initialization for endpoint: %s, region: %s", appS3Cfg.Endpoint, appS3Cfg.Region)
	log.Printf("S3 Init: Applying initial delay of %v...", delayBeforeS3Init)
	time.Sleep(delayBeforeS3Init)

	customResolver := aws.EndpointResolverFunc(func(service, region string) (aws.Endpoint, error) {
		if service == s3.ServiceID {
			endpointURL := appS3Cfg.Endpoint
			if endpointURL != "" && !strings.HasPrefix(endpointURL, "http") {
				endpointURL = "https://" + endpointURL
			}
			log.Printf("S3 Init: EndpointResolver using URL: %s for region: %s", endpointURL, region)
			return aws.Endpoint{
				URL:               endpointURL,
				HostnameImmutable: true,
			}, nil
		}
		return aws.Endpoint{}, &aws.EndpointNotFoundError{}
	})

	sdkLoadOptions := []func(*awsConfig.LoadOptions) error{
		awsConfig.WithCredentialsProvider(credentials.NewStaticCredentialsProvider(accessKey, secretKey, "")),
		awsConfig.WithRegion(appS3Cfg.Region),
		awsConfig.WithEndpointResolver(customResolver),
	}

	sdkCfg, err := awsConfig.LoadDefaultConfig(context.TODO(), sdkLoadOptions...)
	if err != nil {
		return nil, fmt.Errorf("S3 Init: failed to load AWS SDK config: %w", err)
	}

	client := s3.NewFromConfig(sdkCfg)
	storage := &S3Storage{
		Client: client,
		Cfg:    appS3Cfg,
	}

	bucketNames := []string{}
	if appS3Cfg.BucketUserAvatars != "" {
		bucketNames = append(bucketNames, appS3Cfg.BucketUserAvatars)
	}
	if appS3Cfg.BucketTeamImages != "" {
		bucketNames = append(bucketNames, appS3Cfg.BucketTeamImages)
	}

	for i, bucketName := range bucketNames {
		if i > 0 {
			log.Printf("S3 Init: Waiting %v before processing bucket '%s'...", delayBetweenBucketOps, bucketName)
			time.Sleep(delayBetweenBucketOps)
		}
		log.Printf("S3 Init: Processing bucket '%s'...", bucketName)

		err := storage.ensureBucketExistsAndConfigured(bucketName)
		if err != nil {
			log.Printf("S3 Init: Warning - Failed to ensure bucket '%s' is ready: %v. Subsequent S3 operations for this bucket might fail.", bucketName, err)
		} else {
			// fmt.Printf("S3 Bucket '%s' is ready.\n", bucketName) // Логирование уже внутри ensureBucketExistsAndConfigured
		}
	}

	log.Println("S3 Init: S3 client initialization sequence finished.")
	return storage, nil
}

// ensureBucketExistsAndConfigured проверяет, создает бакет (если необходимо) и применяет политику.
func (s *S3Storage) ensureBucketExistsAndConfigured(bucketName string) error {
	log.Printf("S3 Bucket '%s': Checking existence...", bucketName)
	_, err := s.Client.HeadBucket(context.TODO(), &s3.HeadBucketInput{Bucket: aws.String(bucketName)})

	bucketExists := err == nil

	if bucketExists {
		log.Printf("S3 Bucket '%s': Already exists.", bucketName)
	} else {
		// Проверяем тип ошибки, чтобы убедиться, что это "не найдено"
		var apiError interface{ ErrorCode() string } // Общий интерфейс для ошибок AWS SDK
		isNotFoundError := false
		if errors.As(err, &apiError) {
			// s3types.NotFound{} (фактически это *smithy.GenericAPIError) или s3types.NoSuchBucket{}
			// оба возвращают код "NotFound" или "NoSuchBucket"
			errorCode := apiError.ErrorCode()
			if errorCode == "NotFound" || errorCode == "NoSuchBucket" {
				isNotFoundError = true
			}
			log.Printf("S3 Bucket '%s': HeadBucket error - Code: %s, Message: %s", bucketName, errorCode, apiError.ErrorCode())
		} else {
			log.Printf("S3 Bucket '%s': HeadBucket error (unknown type): %v", bucketName, err)
		}

		if isNotFoundError {
			log.Printf("S3 Bucket '%s': Not found by HeadBucket. Attempting to create...", bucketName)
			log.Printf("S3 Bucket '%s': Waiting %v before CreateBucket operation...", bucketName, delayBetweenHeadAndCreate)
			time.Sleep(delayBetweenHeadAndCreate)

			var createBucketCfg *types.CreateBucketConfiguration
			if s.Cfg.Region != "" && s.Cfg.Region != "us-east-1" {
				createBucketCfg = &types.CreateBucketConfiguration{
					LocationConstraint: types.BucketLocationConstraint(s.Cfg.Region),
				}
			}
			_, createErr := s.Client.CreateBucket(context.TODO(), &s3.CreateBucketInput{
				Bucket:                    aws.String(bucketName),
				CreateBucketConfiguration: createBucketCfg,
			})

			if createErr != nil {
				var alreadyOwnedError *types.BucketAlreadyOwnedByYou
				var alreadyExistsError *types.BucketAlreadyExists
				if errors.As(createErr, &alreadyOwnedError) || errors.As(createErr, &alreadyExistsError) {
					log.Printf("S3 Bucket '%s': Already exists (caught during create attempt).", bucketName)
					// Считаем успехом для этого шага, бакет есть
				} else {
					log.Printf("S3 Bucket '%s': Failed to create: %v. Policy application will be skipped.", bucketName, createErr)
					return fmt.Errorf("failed to create bucket '%s': %w", bucketName, createErr) // Возвращаем ошибку, если создание не удалось
				}
			} else {
				log.Printf("S3 Bucket '%s': Successfully created.", bucketName)
			}
		} else {
			// Ошибка при HeadBucket, не связанная с отсутствием бакета (например, 429)
			log.Printf("S3 Bucket '%s': Error checking existence (HeadBucket failed: %v). Policy application will be skipped.", bucketName, err)
			return fmt.Errorf("error during HeadBucket for '%s': %w", bucketName, err) // Возвращаем ошибку
		}
	}

	// Если дошли сюда, значит бакет существует (либо был, либо только что создан)
	// Применяем политику
	log.Printf("S3 Bucket '%s': Waiting %v before applying public read policy...", bucketName, delayAfterCreateOp)
	time.Sleep(delayAfterCreateOp)
	log.Printf("S3 Bucket '%s': Attempting to apply public read policy...", bucketName)

	policyErr := s.applyPublicReadPolicy(bucketName)
	if policyErr != nil {
		log.Printf("S3 Bucket '%s': Warning - Failed to apply public read policy: %v. Objects might not be publicly readable.", bucketName, policyErr)
		// Не возвращаем ошибку policyErr наверх, чтобы не прерывать запуск, если только политика не удалась
	} else {
		log.Printf("S3 Bucket '%s': Public read policy applied/updated successfully.", bucketName)
	}
	log.Printf("S3 Bucket '%s': Waiting %v after policy operation...", bucketName, delayAfterPolicyOp)
	time.Sleep(delayAfterPolicyOp)
	log.Printf("S3 Bucket '%s' is ready.\n", bucketName)
	return nil
}

// applyPublicReadPolicy применяет политику публичного чтения к бакету.
func (s *S3Storage) applyPublicReadPolicy(bucketName string) error {
	policy := fmt.Sprintf(`{
		"Version": "2012-10-17",
		"Statement": [
			{
				"Effect": "Allow",
				"Principal": "*",
				"Action": ["s3:GetObject"], 
				"Resource": "arn:aws:s3:::%s/*" 
			}
		]
	}`, bucketName)

	log.Printf("S3 Bucket '%s': Applying policy: %s", bucketName, policy)
	_, err := s.Client.PutBucketPolicy(context.TODO(), &s3.PutBucketPolicyInput{
		Bucket: aws.String(bucketName),
		Policy: aws.String(policy),
	})

	if err != nil {
		return fmt.Errorf("failed to apply public read policy: %w (check ARN format for your S3 provider)", err)
	}
	return nil
}
