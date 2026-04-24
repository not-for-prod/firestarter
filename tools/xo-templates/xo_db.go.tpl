const Count = "COUNT(*)"

// selectOptions represent select query options.
type selectOptions struct {
	ForUpdate bool
	SkipLocked bool
}

type SelectOption func(*selectOptions)

func ForUpdate() SelectOption {
	return func(o *selectOptions) {
		o.ForUpdate = true
	}
}

func SkipLocked() SelectOption {
	return func(o *selectOptions) {
		o.SkipLocked = true
	}
}

func newSelectOptions(opts ...SelectOption) *selectOptions {
	o := &selectOptions{}

	for _, opt := range opts {
		opt(o)
	}

	return o
}

func ApplySelectOptions(builder squirrel.SelectBuilder, opts ...SelectOption) squirrel.SelectBuilder {
	options := newSelectOptions(opts...)

	if options.ForUpdate {
		builder = builder.Suffix("for update")

		if options.SkipLocked {
			builder = builder.Suffix(" skip locked")
		}
	}

	return builder
}

// XODB is the common interface for database operations that can be used with
// types from schema '{{ schema .Schema }}'.
//
// This should work with database/sql.DB and database/sql.Tx.
type XODB interface {
	Exec(string, ...interface{}) (sql.Result, error)
	Query(string, ...interface{}) (*sql.Rows, error)
	QueryRow(string, ...interface{}) *sql.Row
}

// XOLog provides the log func used by generated queries.
var XOLog = func(string, ...interface{}) { }

// ScannerValuer is the common interface for types that implement both the
// database/sql.Scanner and sql/driver.Valuer interfaces.
type ScannerValuer interface {
	sql.Scanner
	driver.Valuer
}

// StringSlice is a slice of strings.
type StringSlice []string

// quoteEscapeRegex is the regex to match escaped characters in a string.
var quoteEscapeRegex = regexp.MustCompile(`([^\\]([\\]{2})*)\\"`)

// Scan satisfies the sql.Scanner interface for StringSlice.
func (ss *StringSlice) Scan(src interface{}) error {
	buf, ok := src.([]byte)
	if !ok {
		return errors.New("invalid StringSlice")
	}

	// change quote escapes for csv parser
	str := quoteEscapeRegex.ReplaceAllString(string(buf), `$1""`)
	str = strings.Replace(str, `\\`, `\`, -1)

	// remove braces
	str = str[1:len(str)-1]

	// bail if only one
	if len(str) == 0 {
		*ss = StringSlice([]string{})
		return nil
	}

	// parse with csv reader
	cr := csv.NewReader(strings.NewReader(str))
	slice, err := cr.Read()
	if err != nil {
		fmt.Printf("exiting!: %v\n", err)
		return err
	}

	*ss = StringSlice(slice)

	return nil
}

// Value satisfies the driver.Valuer interface for StringSlice.
func (ss StringSlice) Value() (driver.Value, error) {
	v := make([]string, len(ss))
	for i, s := range ss {
		v[i] = `"` + strings.Replace(strings.Replace(s, `\`, `\\\`, -1), `"`, `\"`, -1) + `"`
	}
	return "{" + strings.Join(v, ",") + "}", nil
}

// Slice is a slice of ScannerValuers.
type Slice []ScannerValuer

// Jsonb ...
type Jsonb string

// JSON ...
type JSON string

func argFn(fields []string, tm stom.ToMappable) (res []interface{}, err error) {
	m, err := tm.ToMap()
	if err != nil {
		return nil, err
	}
	for _, v := range fields {
		if value, ok := m[v]; ok {
			if iv, ok := value.(interface{ Valid() bool }); ok {
				if !iv.Valid() {
					res = append(res, nil)
					continue
				}
			}
			if value == nil {
				res = append(res, nil)
				continue
			}
			res = append(res, value)
		} else {
			res = append(res, nil)
		}
	}
	return
}

var (
	reQuestion = regexp.MustCompile(`\$\d`)

	ErrRowAlreadyExists = errors.New("db insert failed: already exists")
	ErrRowMarkedForDeletion = errors.New("db update failed: marked for deletion")
	ErrRowDoesNotExists = errors.New("update failed: does not exist")
)
