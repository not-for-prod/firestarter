package worker

import (
	"context"
	"time"

	"github.com/not-for-prod/observer/tracer/prospan"
)

type Worker interface {
	Disabled() bool
	Job()
	Name() string
	Interval() time.Duration
}

var _ Worker = &Implementation{}

type Implementation struct {
	cfg Config
	job func(ctx context.Context) error
}

func New(cfg Config, job func(ctx context.Context) error) *Implementation {
	return &Implementation{
		cfg: cfg,
		job: job,
	}
}

func (i Implementation) Job() {
	ctx, span := prospan.Start(context.Background())
	defer span.End()

	err := i.job(ctx)
	if err != nil {
		span.Logger().Error("failed to execute job", "name", i.Name(), "error", err)
	}
}

func (i Implementation) Name() string {
	return i.cfg.Name
}

func (i Implementation) Interval() time.Duration {
	return i.cfg.Interval
}

func (i Implementation) Disabled() bool {
	return i.cfg.Disable
}
