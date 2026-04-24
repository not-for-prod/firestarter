package worker

import "time"

type Config struct {
	Disable   bool
	Name      string        `validate:"required"`
	Interval  time.Duration `validate:"required,min=1"`
	BatchSize uint64        `validate:"required,min=1"`
}
