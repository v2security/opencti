package telegram

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"
)

// Sender sends messages via Telegram Bot API.
type Sender struct {
	url    string
	chatID string
	http   *http.Client
}

// NewSender creates a Telegram sender with a 10-second timeout.
func NewSender(botToken, chatID string) *Sender {
	return &Sender{
		url:    fmt.Sprintf("https://api.telegram.org/bot%s/sendMessage", botToken),
		chatID: chatID,
		http:   &http.Client{Timeout: 10 * time.Second},
	}
}

// Send posts a MarkdownV2 message to the configured chat.
func (s *Sender) Send(message string) error {
	payload := map[string]any{
		"chat_id":    s.chatID,
		"text":       message,
		"parse_mode": "MarkdownV2",
	}
	data, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("marshal payload: %w", err)
	}

	resp, err := s.http.Post(s.url, "application/json", bytes.NewReader(data))
	if err != nil {
		return fmt.Errorf("telegram request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		return fmt.Errorf("telegram API error: HTTP %d", resp.StatusCode)
	}
	return nil
}

// mdv2Replacer escapes special characters for Telegram MarkdownV2.
var mdv2Replacer = strings.NewReplacer(
	`\`, `\\`,
	`_`, `\_`,
	`[`, `\[`,
	`]`, `\]`,
	`(`, `\(`,
	`)`, `\)`,
	`~`, `\~`,
	"`", "\\`",
	`>`, `\>`,
	`#`, `\#`,
	`+`, `\+`,
	`-`, `\-`,
	`=`, `\=`,
	`|`, `\|`,
	`{`, `\{`,
	`}`, `\}`,
	`.`, `\.`,
	`!`, `\!`,
)

// Esc escapes user-supplied text for MarkdownV2. Do NOT use on formatting markers.
func Esc(s string) string { return mdv2Replacer.Replace(s) }
