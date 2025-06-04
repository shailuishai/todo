package s3

import (
	"bytes"
	"context"
	"fmt"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types" // Для types.ObjectIdentifier
	"log/slog"
	s3init "server/internal/init/s3" // Пакет инициализации S3 клиента
	"server/internal/modules/user"   // Пакет с ошибками user
)

type ProfileS3 struct {
	log    *slog.Logger
	client *s3.Client // S3 клиент из пакета init
	// bucket string  // Имя бакета теперь будет передаваться в каждый метод
}

// NewProfileS3 теперь принимает только логгер и S3 клиент.
// Имена бакетов будут передаваться из UseCase, который берет их из конфига.
func NewProfileS3(log *slog.Logger, s3Client *s3init.S3Storage) *ProfileS3 {
	return &ProfileS3{
		log:    log,
		client: s3Client.Client, // Используем сам s3.Client
	}
}

// UploadAvatar загружает один файл аватара в указанный бакет с указанным ключом.
func (s *ProfileS3) UploadAvatar(bucketName string, s3Key string, avatarBytes []byte, contentType string) error {
	log := s.log.With(
		slog.String("op", "ProfileS3.UploadAvatar"),
		slog.String("bucket", bucketName),
		slog.String("key", s3Key),
		slog.String("contentType", contentType),
	)

	if contentType == "" {
		contentType = "application/octet-stream" // Default content type
	}

	_, err := s.client.PutObject(context.TODO(), &s3.PutObjectInput{
		Bucket:      aws.String(bucketName),
		Key:         aws.String(s3Key),
		Body:        bytes.NewReader(avatarBytes),
		ContentType: aws.String(contentType),
		// ACL: types.ObjectCannedACLPublicRead, // Если бакеты не публичны по умолчанию
	})

	if err != nil {
		log.Error("failed to upload avatar to S3", "error", err)
		return user.ErrInternal // Ошибка при загрузке на S3
	}

	log.Info("avatar uploaded to S3 successfully")
	return nil
}

// DeleteAvatar удаляет один объект из S3 по бакету и ключу.
func (s *ProfileS3) DeleteAvatar(bucketName string, s3Key string) error {
	log := s.log.With(
		slog.String("op", "ProfileS3.DeleteAvatar"),
		slog.String("bucket", bucketName),
		slog.String("key", s3Key),
	)

	_, err := s.client.DeleteObject(context.TODO(), &s3.DeleteObjectInput{
		Bucket: aws.String(bucketName),
		Key:    aws.String(s3Key),
	})

	if err != nil {
		// Можно проверить специфичные ошибки S3, если нужно (например, NoSuchKey)
		log.Error("failed to delete avatar from S3", "error", err)
		return user.ErrInternal // Ошибка при удалении с S3
	}

	log.Info("avatar deleted from S3 successfully")
	return nil
}

// DeleteAvatars (если нужно удалять несколько размеров одновременно, как в старом коде)
// Эта функция не соответствует текущему упрощенному интерфейсу UploadAvatar/DeleteAvatar,
// но я оставлю ее как пример, если ты решишь вернуться к загрузке нескольких размеров
// и хранению нескольких ключей.
func (s *ProfileS3) DeleteAvatars(bucketName string, s3Keys []string) error {
	log := s.log.With(
		slog.String("op", "ProfileS3.DeleteAvatars"),
		slog.String("bucket", bucketName),
		slog.Any("keys", s3Keys),
	)

	if len(s3Keys) == 0 {
		log.Info("no S3 keys provided for deletion")
		return nil
	}

	var objectsToDelete []types.ObjectIdentifier
	for _, key := range s3Keys {
		objectsToDelete = append(objectsToDelete, types.ObjectIdentifier{Key: aws.String(key)})
	}

	_, err := s.client.DeleteObjects(context.TODO(), &s3.DeleteObjectsInput{
		Bucket: aws.String(bucketName),
		Delete: &types.Delete{
			Objects: objectsToDelete,
			Quiet:   aws.Bool(false), // false - чтобы получить информацию об ошибках для каждого объекта
		},
	})

	if err != nil {
		log.Error("failed to delete objects from S3", "error", err)
		// В ответе DeleteObjectsOutput.Errors можно посмотреть, какие конкретно ключи не удалились.
		return user.ErrInternal
	}

	log.Info("avatars deleted from S3 successfully")
	return nil
}

// GetPublicURL формирует публичный URL для объекта в S3.
// Это вспомогательная функция, которая может быть полезна, если UseCase или DB Repo
// не имеют прямого доступа к s3endpoint.
// endpoint должен быть полным, например "useravatar.storage-321.s3hoster.by" (без https://)
// Или, если бакет является частью хоста, то endpoint "storage-321.s3hoster.by"
// и bucketName "useravatar". Зависит от твоего S3 провайдера.
// Пока что не используется напрямую в интерфейсе Repo, но может пригодиться.
func (s *ProfileS3) GetPublicURL(bucketName string, s3Key string, s3Endpoint string) string {
	if s3Key == "" {
		return ""
	}
	// Формат URL может отличаться для разных S3-совместимых хранилищ.
	// Вариант 1: bucket является частью хоста (например, Amazon S3 по умолчанию)
	// return fmt.Sprintf("https://%s.%s/%s", bucketName, s3Endpoint, s3Key)
	// Вариант 2: bucket является частью пути (часто для MinIO или других)
	return fmt.Sprintf("https://%s/%s/%s", s3Endpoint, bucketName, s3Key)
}
