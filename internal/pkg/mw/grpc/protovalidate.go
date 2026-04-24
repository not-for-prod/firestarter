package grpcmw

import (
	"context"
	"errors"

	"buf.build/go/protovalidate"
	"github.com/not-for-prod/observer/tracer/prospan"
	"github.com/not-for-prod/proterror/proterror"
	"google.golang.org/grpc"
	"google.golang.org/protobuf/proto"
)

func ProtoValidate(validator protovalidate.Validator) grpc.UnaryServerInterceptor {
	return func(
		ctx context.Context,
		req any,
		info *grpc.UnaryServerInfo,
		handler grpc.UnaryHandler,
	) (any, error) {
		ctx, span := prospan.Start(ctx)
		defer span.End()

		// Only validate protobuf messages
		if msg, ok := req.(proto.Message); ok {
			if err := validator.Validate(msg); err != nil {
				return nil, span.Err(
					errors.Join(&proterror.InvalidArgument{}, err),
				)
			}
		}

		// continue with handler
		return handler(ctx, req)
	}
}
