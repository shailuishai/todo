// file: internal/modules/team/repo/s3/team_s3.go
package s3

import (
	"bytes"
	"context"
	"fmt"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"log/slog"
	"server/config"
	s3init "server/internal/init/s3" // Пакет инициализации S3 клиента
	"server/internal/modules/team"   // Для team.ErrTeamInternal и других ошибок S3
	"strings"
)

type TeamS3 struct {
	log    *slog.Logger
	client *s3.Client
	// s3BaseURL должен быть "https://{endpoint}/{bucketForTeamImages}"
	// или просто "https://{bucketForTeamImages}.{endpoint}" если используется virtual-hosted-style
	s3BaseURL string
}

// NewTeamS3 создает новый экземпляр TeamS3.
// s3Client - инициализированный клиент S3.
// s3PublicBaseURL - это полный базовый URL для доступа к файлам в бакете команды,
// например "https://my-bucket.s3.example.com" или "https://s3.example.com/my-bucket-teams"
func NewTeamS3(log *slog.Logger, s3Client *s3init.S3Storage, s3cfg config.S3Config) *TeamS3 {
	return &TeamS3{
		log:       log,
		client:    s3Client.Client,
		s3BaseURL: fmt.Sprintf("https://%s/%s", s3cfg.Endpoint, s3cfg.BucketTeamImages),
	}
}

func (s *TeamS3) UploadTeamImage(bucketName string, s3Key string, imageBytes []byte, contentType string) error {
	op := "TeamS3.UploadTeamImage"
	log := s.log.With(
		slog.String("op", op),
		slog.String("bucket", bucketName),
		slog.String("key", s3Key),
	)

	if contentType == "" {
		contentType = "application/octet-stream"
	}

	_, err := s.client.PutObject(context.TODO(), &s3.PutObjectInput{
		Bucket:      aws.String(bucketName),
		Key:         aws.String(s3Key),
		Body:        bytes.NewReader(imageBytes),
		ContentType: aws.String(contentType),
	})

	if err != nil {
		log.Error("failed to upload team image to S3", "error", err)
		return team.ErrTeamImageUploadFailed
	}
	log.Info("team image uploaded to S3 successfully")
	return nil
}

func (s *TeamS3) DeleteTeamImage(bucketName string, s3Key string) error {
	op := "TeamS3.DeleteTeamImage"
	log := s.log.With(
		slog.String("op", op),
		slog.String("bucket", bucketName),
		slog.String("key", s3Key),
	)

	_, err := s.client.DeleteObject(context.TODO(), &s3.DeleteObjectInput{
		Bucket: aws.String(bucketName),
		Key:    aws.String(s3Key),
	})

	if err != nil {
		log.Error("failed to delete team image from S3", "error", err)
		return team.ErrTeamInternal
	}
	log.Info("team image deleted from S3 successfully")
	return nil
}

// GetTeamImagePublicURL формирует публичный URL для изображения команды.
// s3Key - это ключ объекта в бакете.
// s.s3BaseURL предполагается как "https://endpoint/bucket" или "https://bucket.endpoint"
func (s *TeamS3) GetTeamImagePublicURL(s3Key string) string {
	if s3Key == "" || s.s3BaseURL == "" {
		return ""
	}
	// s.s3BaseURL уже должен быть корректным базовым URL до объектов в бакете
	return fmt.Sprintf("%s/%s", s.s3BaseURL, strings.TrimPrefix(s3Key, "/"))
}
