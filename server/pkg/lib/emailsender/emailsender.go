package emailsender

import (
	"fmt"
	"gopkg.in/gomail.v2"
	"os"
	"server/config"
)

type EmailSender struct {
	SmtpServer *gomail.Dialer
}

func New(cfg config.SMTPConfig) (*EmailSender, error) {
	d := gomail.NewDialer(cfg.Host, cfg.Port, cfg.Username, os.Getenv("YANDEX_EMAIL_PASSWORD"))
	conn, err := d.Dial()
	if err != nil {
		return nil, fmt.Errorf("failed to connect to SMTP server: %w", err)
	}
	defer conn.Close()
	return &EmailSender{d}, nil
}

func (e *EmailSender) SendConfirmEmail(code string, email string) error {
	m := gomail.NewMessage()
	m.SetHeader("From", "OfflinerMen@yandex.by")
	m.SetHeader("To", email)
	m.SetHeader("Subject", "Подтверждение вашей почты")
	body := `<!DOCTYPE html>
    <html lang="ru">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <link rel="preconnect" href="https://fonts.googleapis.com">
        <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
        <link href="https://fonts.googleapis.com/css2?family=Montserrat:ital,wght@0,100..900;1,100..900&display=swap" rel="stylesheet">
        <title>Подтверждение почты</title>
        <style>
            body {
                font-family: "Montserrat", sans-serif;
                background-color: #f4f4f4;
                margin: 0;
                padding: 20px;
            }
            .container {
                max-width: 600px;
                margin: auto;
                background: white;
                padding: 20px;
                border-radius: 5px;
                box-shadow: 0 0 10px rgba(0,0,0,0.1);
            }
            h1 {
                color: #000000;
                font-weight: 900;
                font-size: 32px;
            }
            p {
                font-size: 16px;
                font-weight: 300;
                line-height: 1.5;
                color: #000000;
            }
            .code {
                background: #eee;
                padding: 10px;
                border-radius: 5px;
                font-size: 24px;
                font-weight: bold;
                text-align: center;
                margin: 20px 0;
            }
            .copy-button {
                display: inline-block;
                padding: 10px 15px;
                font-size: 16px;
                color: white;
                background-color: #025ADD;
                border: none;
                border-radius: 5px;
                cursor: pointer;
                text-align: center;
                text-decoration: none;
            }
            .footer {
                font-size: 12px;
                color: #888;
                text-align: center;
                margin-top: 20px;
            }
        </style>
    </head>
    <body>
        <div class="container">
            <h1>Подтверждение вашей почты</h1>
            <p>Здравствуйте!</p>
            <p>Спасибо за регистрацию. Чтобы завершить процесс, пожалуйста, подтвердите вашу почту, введя следующий код:</p>
            <div class="code" id="verificationCode">` + code + `</div>
            <p>Скопируйте код и вставьте его <a href="http://localhost:8080/auth/yandex">на сайте</a> для завершения регистрации.</p>
            <p>Если у вас возникли вопросы, не стесняйтесь обращаться в службу <a href="http://localhost:8080/auth/yandex">поддержки</a>.</p>
        </div>
        <div class="footer">
            <p>&copy; 2024 Offliner. Все права защищены.</p>
        </div>
    </body>
    </html>`
	m.SetBody("text/html", body)
	if err := e.SmtpServer.DialAndSend(m); err != nil {
		return err
	}
	return nil
}
