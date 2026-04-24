package httpmw

import (
	"net/http"

	"github.com/not-for-prod/observer/tracer/prospan"
)

const TraceIDHeaderName = "X-Trace-Id"

func TraceIDHeader(next http.Handler) http.Handler {
	return http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			ctx := r.Context()

			ctxTrace, span := prospan.Start(ctx)
			defer span.End()

			w.Header().Set(TraceIDHeaderName, span.TraceID())

			next.ServeHTTP(w, r.WithContext(ctxTrace))
		},
	)
}
