package main

import (
	"context"

	"firestarter/config"

	"github.com/not-for-prod/observer/logger"
	"github.com/not-for-prod/observer/logger/zap"
	"github.com/not-for-prod/observer/tracer"
	"go.uber.org/fx"
)

type fxLogger struct{}

func newFxLogger() *fxLogger {
	return &fxLogger{}
}

func (l *fxLogger) Printf(msg string, args ...any) {
	logger.Instance().Info(msg, args)
}

func main() {
	logger.SetLogger(zap.NewLogger())
	fx.New(
		fx.Logger(newFxLogger()),
		fx.Invoke(
			config.Instance,
			initLogger,
			initTracer,
		),
	).Run()
}

func initLogger(lc fx.Lifecycle) {
	lc.Append(
		fx.Hook{
			OnStart: func(_ context.Context) error {
				return nil
			},
			OnStop: logger.Stop,
		},
	)
}

func initTracer(lc fx.Lifecycle) {
	tp := tracer.NewProvider(
		tracer.WithHost(config.Instance().Tempo.URL),
		tracer.WithServiceName(config.Instance().Tempo.ServiceName),
		tracer.WithServiceVersion(config.Instance().Tempo.ServiceVersion),
	)
	lc.Append(
		fx.Hook{
			OnStart: func(context.Context) error {
				return tp.Start(context.Background())
			},
			OnStop: func(ctx context.Context) error {
				return tp.Stop(ctx)
			},
		},
	)
}
