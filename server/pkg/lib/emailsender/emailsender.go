package emailsender

import (
	"errors"
	"fmt"
	"gopkg.in/gomail.v2"
	"log/slog" // <<< ДОБАВЛЕН ЛОГГЕР
	"os"
	"server/config"
	"time"
)

type EmailSender struct {
	dialer    *gomail.Dialer // Переименовал SmtpServer в dialer для ясности
	fromEmail string
	log       *slog.Logger // <<< ДОБАВЛЕН ЛОГГЕР
}

// New создает новый EmailSender.
// logger может быть nil, тогда будет использоваться slog.Default().
func New(cfg config.SMTPConfig, logger *slog.Logger) (*EmailSender, error) {
	if logger == nil {
		logger = slog.Default() // Фоллбэк на дефолтный логгер
	}
	log := logger.With(slog.String("component", "EmailSender"))

	password := os.Getenv("YANDEX_EMAIL_PASSWORD") // Или другой способ получения пароля
	if password == "" {
		log.Error("SMTP password (YANDEX_EMAIL_PASSWORD) is not set.")
		// Возвращаем ошибку, если пароль критичен для инициализации
		// return nil, errors.New("SMTP password not configured")
	}

	d := gomail.NewDialer(cfg.Host, cfg.Port, cfg.Username, password)

	// Проверка соединения при создании (опционально, но полезно)
	conn, err := d.Dial()
	if err != nil {
		log.Error("Failed to connect to SMTP server", "host", cfg.Host, "port", cfg.Port, "user", cfg.Username, "error", err)
		return nil, fmt.Errorf("failed to connect to SMTP server %s:%d for user %s: %w", cfg.Host, cfg.Port, cfg.Username, err)
	}
	if err := conn.Close(); err != nil {
		log.Warn("Error closing test SMTP connection", "error", err)
		// Не фатально, но стоит залогировать
	}
	log.Info("EmailSender initialized and test connection successful", "host", cfg.Host, "user", cfg.Username)

	return &EmailSender{dialer: d, fromEmail: cfg.Username, log: log}, nil
}

// SendEmail - общий метод для отправки email.
func (e *EmailSender) SendEmail(recipientEmail, subject, htmlBody, textBody string) error {
	op := "EmailSender.SendEmail"
	log := e.log.With(slog.String("op", op), slog.String("to", recipientEmail), slog.String("subject", subject))

	m := gomail.NewMessage()
	m.SetHeader("From", e.fromEmail)
	m.SetHeader("To", recipientEmail)
	m.SetHeader("Subject", subject)

	if htmlBody != "" {
		m.SetBody("text/html", htmlBody)
		if textBody != "" { // Если есть и HTML, и текст, добавляем альтернативу
			m.AddAlternative("text/plain", textBody)
		}
	} else if textBody != "" {
		m.SetBody("text/plain", textBody)
	} else {
		log.Warn("Attempting to send email with empty body")
		return errors.New("email body is empty")
	}

	if err := e.dialer.DialAndSend(m); err != nil {
		log.Error("Failed to send email", "error", err)
		return fmt.Errorf("failed to send email to %s: %w", recipientEmail, err)
	}
	log.Info("Email sent successfully")
	return nil
}

// SendConfirmEmail остается для обратной совместимости или как удобный wrapper.
func (e *EmailSender) SendConfirmEmail(code string, recipientEmail string) error {
	//op := "EmailSender.SendConfirmEmail"
	//log := e.log.With(slog.String("op", op), slog.String("to", recipientEmail))

	subject := "Подтверждение вашей почты для ToDo App"
	// HTML тело письма (как было, можно вынести в шаблоны)
	htmlBody := `<!DOCTYPE html>
    <html lang="ru">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <link rel="preconnect" href="https://fonts.googleapis.com">
        <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
        <link href="https://fonts.googleapis.com/css2?family=Montserrat:ital,wght@0,100..900;1,100..900&display=swap" rel="stylesheet">
        <title>Подтверждение почты - ToDo App</title>
        <style>
            body { font-family: "Montserrat", sans-serif; background-color: #f4f4f4; margin: 0; padding: 20px; color: #333; }
            .container { max-width: 600px; margin: auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
            h1 { color: #2c3e50; font-weight: 700; font-size: 28px; text-align: center; }
            p { font-size: 16px; font-weight: 400; line-height: 1.6; color: #333; }
            .code-container { background: #e9ecef; padding: 15px 20px; border-radius: 5px; text-align: center; margin: 25px 0; }
            .code-label { font-size: 14px; color: #555; margin-bottom: 5px; }
            .code { font-size: 28px; font-weight: bold; color: #025ADD; letter-spacing: 2px; }
            .instructions { text-align: center; margin-top: 15px; }
            .footer { font-size: 12px; color: #777; text-align: center; margin-top: 30px; padding-top: 15px; border-top: 1px solid #eee; }
        </style>
    </head>
    <body>
        <div class="container">
            <h1>Подтверждение вашей почты</h1>
            <p>Здравствуйте!</p>
            <p>Спасибо за регистрацию в ToDo App. Чтобы активировать ваш аккаунт, пожалуйста, используйте следующий код подтверждения:</p>
            <div class="code-container">
                <div class="code-label">Ваш код подтверждения:</div>
                <div class="code">` + code + `</div>
            </div>
            <p class="instructions">Пожалуйста, введите этот код в соответствующее поле в приложении ToDo App или на странице подтверждения на нашем сайте.</p>
            <p>Если вы не регистрировались в ToDo App, пожалуйста, проигнорируйте это письмо.</p>
        </div>
        <div class="footer">
            <p>© ` + fmt.Sprint(time.Now().Year()) + ` ToDo App. Все права защищены.</p>
        </div>
    </body>
    </html>`

	// Plain text версия для email клиентов, не поддерживающих HTML
	textBody := fmt.Sprintf(
		"Здравствуйте!\n\nСпасибо за регистрацию в ToDo App. Ваш код подтверждения: %s\n\nПожалуйста, введите этот код в приложении или на сайте.\nЕсли вы не регистрировались, проигнорируйте это письмо.\n\n© %d ToDo App.",
		code,
		time.Now().Year(),
	)

	return e.SendEmail(recipientEmail, subject, htmlBody, textBody)
}
