# firestarter

## Prerequisites

go install

```shell
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
```

pre-commit 

```shell
pre-commit install --config .pre-commit-config.yaml
```

### Goland File and Code Templates

- proto

  ```
  syntax = "proto3";
  
  package ${DIR_PATH.replace("/", ".").replace("api.", "")};
  ```

- infra ifce

    ```
    #set( $CapName = $NAME.substring(0,1).toUpperCase() + $NAME.substring(1) )

    package ${GO_PACKAGE_NAME}
    
    //go:generate moq -out ${NAME}_moq.go . $CapName
    //go:generate implgen --src ${FILE_NAME} --interface-name $CapName --mod-relative --dst internal/infrastructure/${GO_PACKAGE_NAME} --impl-package ${NAME}_repository
    
    type $CapName interface {

    }
    ```

- app ifce

  ```
  #set( $CapName = $NAME.substring(0,1).toUpperCase() + $NAME.substring(1) )

  package ${GO_PACKAGE_NAME}

  //go:generate moq -out ${NAME}_moq.go . $CapName
  //go:generate implgen --src ${FILE_NAME} --interface-name $CapName --mod-relative --dst internal/application/${GO_PACKAGE_NAME} --impl-package ${NAME}_service

  type $CapName interface {

  }
  ```

- repository

  ```
  package ${GO_PACKAGE_NAME}
  
  import (
      "context"
  
      trm "github.com/avito-tech/go-transaction-manager/sqlx"
      "github.com/jmoiron/sqlx"
  )
  
  var sq = squirrel.StatementBuilder.PlaceholderFormat(squirrel.Dollar)
  
  type Implementation struct {
      db        *sqlx.DB
      ctxGetter *trm.CtxGetter
  }
  
  func NewImplementation(db *sqlx.DB, ctxGetter *trm.CtxGetter) *Implementation {
      return &Implementation{
          db:        db,
          ctxGetter: ctxGetter,
      }
  }
  
  func (i *Implementation) tr(ctx context.Context) trm.Tr {
      return i.ctxGetter.DefaultTrOrDB(ctx, i.db)
  }
  
  ```