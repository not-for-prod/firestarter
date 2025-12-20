# ==================================================================================== #
# PREPARE
# ==================================================================================== #

.PHONY: dependency
dependency:
	# mocks
	go install https://github.com/matryer/moq@latest
	# migrations
	go install github.com/pressly/goose/v3/cmd/goose@latest
	# reverse orm
	go install github.com/not-for-prod/xo-templates@latest
	# proto plugins
	go install github.com/not-for-prod/proterror/cmd/protoc-gen-proterror@latest
	go install github.com/not-for-prod/clay/cmd/protoc-gen-goclay@latest
	# code generators
	go install github.com/not-for-prod/implgen@latest

# ==================================================================================== #
# INFRASTRUCTURE
# ==================================================================================== #

.PHONY: infra ## поднимает инфрастуктуру для проекта
.SILENCE:
infra:
	docker-compose -f ./docker-compose.yaml up -d --build --force-recreate --wait

infra-stop:
	docker-compose -f ./docker-compose.yaml down

# ==================================================================================== #
# MIGRATIONS
# ==================================================================================== #

DB_NAME=postgres
DB_PASS=postgres
DB_USER=postgres
DB_PORT=5432
MIGRATION_FOLDER=./tools/migrations

.PHONY: migrations-up ## накатывает миграции на базу данных
migrations-up:
	goose postgres 'host=localhost port=${DB_PORT} user=${DB_USER} sslmode=disable dbname=${DB_NAME}' -dir ${MIGRATION_FOLDER} -allow-missing up

.PHONY: migrations-reset ## накатывает миграции на базу данных
migrations-reset:
	goose postgres 'host=localhost port=${DB_PORT} user=${DB_USER} sslmode=disable dbname=${DB_NAME}' -dir ${MIGRATION_FOLDER} -allow-missing reset

.PHONY: migrations ## накатывает миграции на базу данных
migrations: migrations-reset migrations-up

# ==================================================================================== #
# CODEGEN
# ==================================================================================== #

XO_OUTPUT_PATH=./internal/generated/xo
XO_TEMPLATE_PATH=./tools/xo_templates
.PHONY: xo ## генерация dto базы данных
xo:
	rm -rf $(XO_OUTPUT_PATH)
	mkdir -p $(XO_OUTPUT_PATH)
	xo "pgsql://$(DB_USER)@localhost:$(DB_PORT)/$(DB_NAME)?sslmode=disable" \
	-o $(XO_OUTPUT_PATH) --template-path $(XO_TEMPLATE_PATH) --schema public --suffix ".xo.go" --custom-type-package custom

pb:
	buf dep update
	buf dep prune
	buf lint
	#buf breaking --against ".git#subdir=."
	buf generate

generate: pb xo
	go generate ./...

# ==================================================================================== #
# LINTER
# ==================================================================================== #

linter:
	golangci-lint --config .golangci.yaml run

fmt:
	golangci-lint --config .golangci.yaml fmt