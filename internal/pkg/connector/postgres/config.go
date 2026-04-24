package postgres

import "time"

type Config struct {
	DSN                string        `validate:"required"`
	MaxConnections     int32         `validate:"required,min=1"`
	MinConnections     int32         `validate:"required,min=1"`
	MinIdleConnections int32         `validate:"required,min=1"`
	MaxConnLifetime    time.Duration `validate:"required"`
}
