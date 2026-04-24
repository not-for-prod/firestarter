package postgres

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
)

func New(cfg Config) (*pgxpool.Pool, error) {
	ctx := context.Background()

	dsnCfg, err := pgxpool.ParseConfig(cfg.DSN)
	if err != nil {
		return nil, err
	}

	dsnCfg.MaxConns = cfg.MaxConnections
	dsnCfg.MinConns = cfg.MinConnections
	dsnCfg.MinIdleConns = cfg.MinIdleConnections
	dsnCfg.MaxConnLifetime = cfg.MaxConnLifetime

	pool, err := pgxpool.NewWithConfig(ctx, dsnCfg)
	if err != nil {
		return nil, err
	}

	return pool, nil
}
