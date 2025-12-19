package config

import (
	"errors"
	"fmt"
	"log"
	"os"
	"os/exec"
	"strings"
	"sync"
	"time"

	"github.com/go-playground/validator/v10"
	"github.com/spf13/viper"
)

type Config struct {
	Tempo struct {
		URL            string `validate:"required"`
		ServiceName    string `validate:"required"`
		ServiceVersion string `validate:"required"`
	}
	CORS struct {
		AllowedOrigins   []string
		AllowedMethods   []string
		AllowedHeaders   []string
		ExposedHeaders   []string
		AllowCredentials bool
		MaxAge           int
	}
}

type Worker struct {
	Disable   bool
	Interval  time.Duration `validate:"required,min=1"`
	BatchSize uint64        `validate:"required,min=1"`
}

var (
	once   sync.Once
	config *Config
)

func Instance() *Config {
	if config == nil {
		once.Do(
			func() {
				var err error

				path := "./config/config.yaml"

				root, err := getGoModRoot()
				if err == nil {
					path = root + "/config/config.yaml"
				}

				viperCfg, err := loadConfig(path)
				if err != nil {
					log.Fatalf("error loading config file: %s", err)
				}

				cfg, err := parseConfig(viperCfg)
				if err != nil {
					log.Fatalf("error parsing config file: %s", err)
				}

				config = cfg
			},
		)
	}

	return config
}

// getGoModRoot returns the absolute path to the root directory containing go.mod.
func getGoModRoot() (string, error) {
	output, err := exec.Command("go", "list", "-m", "-f", "{{.Dir}}").Output()
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(output)), nil
}

func loadConfig(path string) (*viper.Viper, error) {
	v := viper.New()

	configRAW, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("can't load config file %s: %s", path, err)
	}

	v.SetConfigName("config")
	v.SetConfigType("yaml")
	if err := v.ReadConfig(configRAW); err != nil {
		if _, ok := err.(viper.ConfigFileNotFoundError); ok {
			return nil, errors.New("config file not found")
		}

		return nil, err
	}

	return v, nil
}

func parseConfig(v *viper.Viper) (*Config, error) {
	var c Config

	err := v.Unmarshal(&c)
	if err != nil {
		log.Printf("unable to decode into struct, %v", err)
		return nil, err
	}

	err = validator.New().Struct(&c)
	if err != nil {
		return nil, fmt.Errorf("can't validate config: %s", err.Error())
	}

	return &c, nil
}
