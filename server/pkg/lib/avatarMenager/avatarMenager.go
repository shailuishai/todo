package avatarManager

import (
	"bytes"
	"errors"
	"github.com/chai2010/webp"
	"github.com/nfnt/resize"
	"image"
	"image/gif"
	"image/jpeg"
	"image/png"
	"io"
	"mime/multipart"
	"net/http"
	"sync"
)

var (
	ErrInternal                = errors.New("internal server error")
	ErrInvalidTypeAvatar       = errors.New("invalid type avatar, supported avatar formats are jpg, jpeg, png, webp, or no animated gif")
	ErrInvalidResolutionAvatar = errors.New("invalid resolution avatar, supported avatar resolution 1x1")
	ErrInvalidTypePoster       = errors.New("invalid type poster, supported avatar formats are jpg, jpeg, png, webp, or no animated gif")
	ErrInvalidResolutionPoster = errors.New("invalid resolution poster, supported poster resolution 800x1200")
)

func ParsingAvatarImage(file *multipart.File) ([]byte, []byte, error) {
	buffer := new(bytes.Buffer)
	if _, err := io.Copy(buffer, *file); err != nil {
		return nil, nil, ErrInternal
	}

	var img image.Image
	var err error
	contentType := http.DetectContentType(buffer.Bytes())

	switch contentType {
	case "image/png":
		img, err = png.Decode(buffer)
	case "image/jpeg":
		img, err = jpeg.Decode(buffer)
	case "image/gif":
		isNonAnimated, err := isNonAnimatedGIF(bytes.NewReader(buffer.Bytes()))
		if err != nil || !isNonAnimated {
			return nil, nil, ErrInvalidTypeAvatar
		}
		img, err = gif.Decode(buffer)
	case "image/webp":
		img, err = webp.Decode(buffer)
	default:
		return nil, nil, ErrInvalidTypeAvatar
	}

	if err != nil {
		return nil, nil, ErrInvalidTypeAvatar
	}

	bounds := img.Bounds()
	width := bounds.Dx()
	height := bounds.Dy()

	if width != height {
		return nil, nil, ErrInvalidResolutionAvatar
	}

	var wg sync.WaitGroup
	var buf512, buf64 []byte
	var err512, err64 error

	// Обработка 512x512
	wg.Add(1)
	go func() {
		defer wg.Done()
		resized := resize.Resize(512, 512, img, resize.Lanczos3)
		buffer := new(bytes.Buffer)
		if err := webp.Encode(buffer, resized, &webp.Options{Quality: 80}); err != nil {
			err512 = ErrInternal
			return
		}
		buf512 = buffer.Bytes()
	}()

	// Обработка 52x52
	wg.Add(1)
	go func() {
		defer wg.Done()
		resized := resize.Resize(64, 64, img, resize.Lanczos3)
		buffer := new(bytes.Buffer)
		if err := webp.Encode(buffer, resized, &webp.Options{Quality: 80}); err != nil {
			err64 = ErrInternal
			return
		}
		buf64 = buffer.Bytes()
	}()

	// Ожидание завершения всех горутин
	wg.Wait()

	// Проверка на ошибки
	if err512 != nil {
		return nil, nil, err512
	}
	if err64 != nil {
		return nil, nil, err64
	}

	return buf64, buf512, nil
}

func ParsingPosterImage(file *multipart.File) ([]byte, []byte, error) {
	buffer := new(bytes.Buffer)
	if _, err := io.Copy(buffer, *file); err != nil {
		return nil, nil, ErrInternal
	}

	var img image.Image
	var err error
	contentType := http.DetectContentType(buffer.Bytes())

	switch contentType {
	case "image/png":
		img, err = png.Decode(buffer)
	case "image/jpeg":
		img, err = jpeg.Decode(buffer)
	case "image/gif":
		isNonAnimated, err := isNonAnimatedGIF(bytes.NewReader(buffer.Bytes()))
		if err != nil || !isNonAnimated {
			return nil, nil, ErrInvalidTypePoster
		}
		img, err = gif.Decode(buffer)
	case "image/webp":
		img, err = webp.Decode(buffer)
	default:
		return nil, nil, ErrInvalidTypePoster
	}

	if err != nil {
		return nil, nil, ErrInvalidTypePoster
	}

	bounds := img.Bounds()
	width := bounds.Dx()
	height := bounds.Dy()

	// Проверка на минимальное разрешение постера
	if width < 800 || height < 1200 {
		return nil, nil, ErrInvalidResolutionPoster
	}

	var wg sync.WaitGroup
	var bufLarge, bufThumbnail []byte
	var errLarge, errThumbnail error

	// Обработка большого постера (800x1200)
	wg.Add(1)
	go func() {
		defer wg.Done()
		resized := resize.Resize(800, 1200, img, resize.Lanczos3)
		buffer := new(bytes.Buffer)
		if err := webp.Encode(buffer, resized, &webp.Options{Quality: 85}); err != nil {
			errLarge = ErrInternal
			return
		}
		bufLarge = buffer.Bytes()
	}()

	// Обработка миниатюры постера (200x300)
	wg.Add(1)
	go func() {
		defer wg.Done()
		resized := resize.Resize(200, 300, img, resize.Lanczos3)
		buffer := new(bytes.Buffer)
		if err := webp.Encode(buffer, resized, &webp.Options{Quality: 85}); err != nil {
			errThumbnail = ErrInternal
			return
		}
		bufThumbnail = buffer.Bytes()
	}()

	// Ожидание завершения всех горутин
	wg.Wait()

	// Проверка на ошибки
	if errLarge != nil {
		return nil, nil, errLarge
	}
	if errThumbnail != nil {
		return nil, nil, errThumbnail
	}

	return bufThumbnail, bufLarge, nil
}

func isNonAnimatedGIF(reader io.Reader) (bool, error) {
	img, err := gif.DecodeAll(reader)
	if err != nil {
		return false, err
	}
	return len(img.Image) == 1, nil
}
