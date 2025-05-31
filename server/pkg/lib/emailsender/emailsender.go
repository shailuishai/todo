package emailsender

import (
	"fmt"
	"gopkg.in/gomail.v2"
	"os"
	"server/config" // Убедись, что config.SMTPConfig импортируется
	"time"
)

type EmailSender struct {
	SmtpServer *gomail.Dialer
	fromEmail  string // Добавим поле для email отправителя
}

func New(cfg config.SMTPConfig) (*EmailSender, error) {
	// Используем cfg.Username и os.Getenv("YANDEX_EMAIL_PASSWORD")
	// YANDEX_EMAIL_PASSWORD должен быть паролем приложения для cfg.Username
	d := gomail.NewDialer(cfg.Host, cfg.Port, cfg.Username, os.Getenv("YANDEX_EMAIL_PASSWORD"))

	// Проверка соединения при создании Dialera (опционально, но полезно для быстрой диагностики)
	conn, err := d.Dial()
	if err != nil {
		return nil, fmt.Errorf("failed to connect to SMTP server %s:%d for user %s: %w", cfg.Host, cfg.Port, cfg.Username, err)
	}
	defer conn.Close() // Закрываем тестовое соединение

	return &EmailSender{SmtpServer: d, fromEmail: cfg.Username}, nil
}

func (e *EmailSender) SendConfirmEmail(code string, recipientEmail string) error {
	m := gomail.NewMessage()
	m.SetHeader("From", e.fromEmail) // Используем email из конструктора
	m.SetHeader("To", recipientEmail)
	m.SetHeader("Subject", "Подтверждение вашей почты для ToDo App") // Уточнил тему
	// TODO: Ссылка "на сайте" должна вести на страницу фронтенда, где пользователь вводит код.
	// Например, frontend_url/confirm-email или что-то подобное.
	// Текущая ссылка href="http://localhost:8080/auth/yandex" нерелевантна для ввода кода.
	// Лучше просто написать "введите этот код в приложении" или "на странице подтверждения email на нашем сайте".
	body := `<!DOCTYPE html>
    <html lang="ru">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <link rel="preconnect" href="https://fonts.googleapis.com">
        <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
        <link href="https://fonts.googleapis.com/css2?family=Montserrat:ital,wght@0,100..900;1,100..900&display=swap" rel="stylesheet">
        <title>Подтверждение почты - ToDo App</title>
        <style>
            body {
                font-family: "Montserrat", sans-serif;
                background-color: #f4f4f4;
                margin: 0;
                padding: 20px;
                color: #333;
            }
            .container {
                max-width: 600px;
                margin: auto;
                background: white;
                padding: 20px;
                border-radius: 8px;
                box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            }
            h1 {
                color: #2c3e50; /* Темно-синий */
                font-weight: 700; /* Немного легче, чем 900 */
                font-size: 28px; /* Чуть меньше */
                text-align: center;
            }
            p {
                font-size: 16px;
                font-weight: 400; /* Стандартный вес */
                line-height: 1.6;
                color: #333;
            }
            .code-container {
                background: #e9ecef; /* Светло-серый фон */
                padding: 15px 20px;
                border-radius: 5px;
                text-align: center;
                margin: 25px 0;
            }
            .code-label {
                font-size: 14px;
                color: #555;
                margin-bottom: 5px;
            }
            .code {
                font-size: 28px; /* Крупнее для кода */
                font-weight: bold;
                color: #025ADD; /* Акцентный цвет */
                letter-spacing: 2px; /* Небольшой интервал между символами */
            }
            .instructions {
                text-align: center;
                margin-top: 15px;
            }
            .footer {
                font-size: 12px;
                color: #777; /* Светлее */
                text-align: center;
                margin-top: 30px;
                padding-top: 15px;
                border-top: 1px solid #eee;
            }
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
	m.SetBody("text/html", body)

	// DialAndSend открывает новое соединение для каждого письма.
	// Если отправляется много писем, лучше использовать открытое соединение.
	// Но для одного письма подтверждения это нормально.
	if err := e.SmtpServer.DialAndSend(m); err != nil {
		// Здесь можно добавить более детальное логирование ошибки перед возвратом
		// log.Error("failed to send confirmation email", "to", recipientEmail, "error", err)
		return fmt.Errorf("failed to send confirmation email to %s: %w", recipientEmail, err)
	}
	return nil
}
