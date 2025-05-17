package s3

import (
	"bytes"
	"context"
	"fmt"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
	"log/slog"
	s3Storage "server/internal/init/s3"
	u "server/internal/modules/user"
	"sync"
)

type ProfileS3 struct {
	log    *slog.Logger
	s3     *s3Storage.S3Storage
	bucket string
}

func NewProfileS3(log *slog.Logger, s3 *s3Storage.S3Storage) *ProfileS3 {
	return &ProfileS3{
		log:    log,
		s3:     s3,
		bucket: "useravatar",
	}
}

func (s *ProfileS3) UploadAvatar(avatarSmall []byte, avatarLarge []byte, login string, userId uint) (*string, error) {
	s.log = s.log.With("op", "uploadAvatar")

	folderPath := fmt.Sprintf("%s_%d/", login, userId)

	objectKeySmall := folderPath + "64x64.webp"
	objectKeyLarge := folderPath + "512x512.webp"

	var wg sync.WaitGroup
	var errSmall, errLarge error

	wg.Add(1)
	go func() {
		defer wg.Done()

		uploadInputSmall := &s3.PutObjectInput{
			Bucket:      aws.String(s.bucket),
			Key:         aws.String(objectKeySmall),
			Body:        bytes.NewReader(avatarSmall),
			ContentType: aws.String("image/webp"),
		}

		_, errSmall = s.s3.Client.PutObject(context.TODO(), uploadInputSmall)
		return
	}()

	wg.Add(1)
	go func() {
		defer wg.Done()

		uploadInputLarge := &s3.PutObjectInput{
			Bucket:      aws.String(s.bucket),
			Key:         aws.String(objectKeyLarge),
			Body:        bytes.NewReader(avatarLarge),
			ContentType: aws.String("image/webp"),
		}

		_, errLarge = s.s3.Client.PutObject(context.TODO(), uploadInputLarge)
		return
	}()

	wg.Wait()

	if errSmall != nil || errLarge != nil {
		s.log.Error("uploadAvatar err", "err", errSmall, "err", errLarge)
		return nil, u.ErrInternal
	}

	folderURL := fmt.Sprintf("https://%s.%s/%s", s.bucket, s.s3.Endpoint, folderPath)
	return &folderURL, nil
}

func (s *ProfileS3) DeleteAvatar(login string, userId uint) error {
	folderPath := fmt.Sprintf("%s_%d/", login, userId)

	objectsToDelete := []string{folderPath + "64x64.wabp", folderPath + "512x512.webp"}

	var objectsId []types.ObjectIdentifier
	objectsId = append(objectsId, types.ObjectIdentifier{Key: aws.String(objectsToDelete[0])})
	objectsId = append(objectsId, types.ObjectIdentifier{Key: aws.String(objectsToDelete[1])})

	deleteInput := &s3.DeleteObjectsInput{
		Bucket: aws.String(s.bucket),
		Delete: &types.Delete{
			Objects: objectsId,
			Quiet:   aws.Bool(true),
		},
	}

	_, err := s.s3.Client.DeleteObjects(context.TODO(), deleteInput)

	return err
}
