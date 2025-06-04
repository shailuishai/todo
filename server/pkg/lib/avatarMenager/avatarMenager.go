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
	// "mime/multipart" // Больше не нужен, если принимаем io.Reader
	"net/http"
	"sync"
)

var (
	ErrInternal                = errors.New("internal server error")
	ErrInvalidTypeAvatar       = errors.New("invalid type avatar, supported avatar formats are jpg, jpeg, png, webp, or no animated gif")
	ErrInvalidResolutionAvatar = errors.New("invalid resolution avatar, supported avatar resolution 1x1")
	ErrInvalidTypePoster       = errors.New("invalid type poster, supported avatar formats are jpg, jpeg, png, webp, or no animated gif")
	ErrInvalidResolutionPoster = errors.New("invalid resolution poster, supported poster resolution 800x1200")
	ErrInvalidSizeAvatar       = errors.New("sasdf")
)

// ИЗМЕНЕНА СИГНАТУРА: принимает io.Reader
func ParsingAvatarImage(reader io.Reader) ([]byte, []byte, error) {
	buffer := new(bytes.Buffer)
	// Копируем данные из reader в buffer. Reader может быть прочитан только один раз.
	// Поэтому, если contentType также нужен из buffer, его нужно определять после копирования.
	// Или, если multipart.FileHeader доступен, contentType можно взять оттуда.
	// Но http.DetectContentType работает с []byte.
	if _, err := io.Copy(buffer, reader); err != nil {
		return nil, nil, ErrInternal // Ошибка чтения из источника
	}

	// Важно: после io.Copy(buffer, reader) сам reader уже прочитан.
	// Все последующие операции должны использовать buffer.Bytes() или bytes.NewReader(buffer.Bytes()).

	var img image.Image
	var err error
	// Определяем тип контента по байтам из буфера
	contentType := http.DetectContentType(buffer.Bytes())

	// Для декодирования нужно снова создать reader из буфера, т.к. buffer.Read() сдвигает указатель
	imageDataReader := bytes.NewReader(buffer.Bytes())

	switch contentType {
	case "image/png":
		img, err = png.Decode(imageDataReader)
	case "image/jpeg":
		img, err = jpeg.Decode(imageDataReader)
	case "image/gif":
		// isNonAnimatedGIF также ожидает io.Reader
		gifReaderForCheck := bytes.NewReader(buffer.Bytes())
		isNonAnimated, nonAnimatedErr := isNonAnimatedGIF(gifReaderForCheck)
		if nonAnimatedErr != nil {
			return nil, nil, ErrInvalidTypeAvatar // Ошибка проверки GIF
		}
		if !isNonAnimated {
			return nil, nil, ErrInvalidTypeAvatar // Анимированный GIF
		}
		// Декодируем GIF заново
		gifReaderForDecode := bytes.NewReader(buffer.Bytes())
		img, err = gif.Decode(gifReaderForDecode)
	case "image/webp":
		img, err = webp.Decode(imageDataReader)
	default:
		return nil, nil, ErrInvalidTypeAvatar
	}

	if err != nil {
		// err уже содержит информацию об ошибке декодирования
		return nil, nil, ErrInvalidTypeAvatar // Можно обернуть err, если нужно: fmt.Errorf("%w: %v", ErrInvalidTypeAvatar, err)
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

	wg.Add(1)
	go func() {
		defer wg.Done()
		resized := resize.Resize(512, 512, img, resize.Lanczos3)
		imgBuffer := new(bytes.Buffer) // Локальный буфер для этой горутины
		if encErr := webp.Encode(imgBuffer, resized, &webp.Options{Quality: 80}); encErr != nil {
			err512 = ErrInternal // Можно сделать более специфичную ошибку
			return
		}
		buf512 = imgBuffer.Bytes()
	}()

	wg.Add(1)
	go func() {
		defer wg.Done()
		resized := resize.Resize(64, 64, img, resize.Lanczos3)
		imgBuffer := new(bytes.Buffer) // Локальный буфер
		if encErr := webp.Encode(imgBuffer, resized, &webp.Options{Quality: 80}); encErr != nil {
			err64 = ErrInternal
			return
		}
		buf64 = imgBuffer.Bytes()
	}()

	wg.Wait()

	if err512 != nil {
		return nil, nil, err512
	}
	if err64 != nil {
		return nil, nil, err64
	}

	return buf64, buf512, nil
}

// Аналогично изменить ParsingPosterImage, если используется
func ParsingPosterImage(reader io.Reader) ([]byte, []byte, error) {
	// ... похожая логика с io.Copy в buffer и использованием bytes.NewReader(buffer.Bytes()) для декодеров ...
	buffer := new(bytes.Buffer)
	if _, err := io.Copy(buffer, reader); err != nil {
		return nil, nil, ErrInternal
	}
	// ... остальная логика аналогична ParsingAvatarImage, только с другими размерами и проверками
	var img image.Image
	var err error
	contentType := http.DetectContentType(buffer.Bytes())
	imageDataReader := bytes.NewReader(buffer.Bytes())

	switch contentType {
	case "image/png":
		img, err = png.Decode(imageDataReader)
	case "image/jpeg":
		img, err = jpeg.Decode(imageDataReader)
	case "image/gif":
		gifReaderForCheck := bytes.NewReader(buffer.Bytes())
		isNonAnimated, nonAnimatedErr := isNonAnimatedGIF(gifReaderForCheck)
		if nonAnimatedErr != nil {
			return nil, nil, ErrInvalidTypePoster
		}
		if !isNonAnimated {
			return nil, nil, ErrInvalidTypePoster
		}
		gifReaderForDecode := bytes.NewReader(buffer.Bytes())
		img, err = gif.Decode(gifReaderForDecode)
	case "image/webp":
		img, err = webp.Decode(imageDataReader)
	default:
		return nil, nil, ErrInvalidTypePoster
	}

	if err != nil {
		return nil, nil, ErrInvalidTypePoster
	}

	bounds := img.Bounds()
	width := bounds.Dx()
	height := bounds.Dy()

	if width < 800 || height < 1200 { // Примерные размеры для постера
		return nil, nil, ErrInvalidResolutionPoster
	}

	var wg sync.WaitGroup
	var bufLarge, bufThumbnail []byte
	var errLarge, errThumbnail error

	wg.Add(1)
	go func() {
		defer wg.Done()
		resized := resize.Resize(800, 1200, img, resize.Lanczos3) // Размеры для постера
		imgBuffer := new(bytes.Buffer)
		if encErr := webp.Encode(imgBuffer, resized, &webp.Options{Quality: 85}); encErr != nil {
			errLarge = ErrInternal
			return
		}
		bufLarge = imgBuffer.Bytes()
	}()

	wg.Add(1)
	go func() {
		defer wg.Done()
		resized := resize.Resize(200, 300, img, resize.Lanczos3) // Размеры для thumbnail
		imgBuffer := new(bytes.Buffer)
		if encErr := webp.Encode(imgBuffer, resized, &webp.Options{Quality: 85}); encErr != nil {
			errThumbnail = ErrInternal
			return
		}
		bufThumbnail = imgBuffer.Bytes()
	}()

	wg.Wait()
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
