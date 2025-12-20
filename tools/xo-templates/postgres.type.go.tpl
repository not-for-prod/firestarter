{{ $prefix := .Name }}
{{ $table_name := .Table.TableName }}

// zero{{ $prefix }} zero value of dto
var zero{{ $prefix }} = {{ $prefix }}{}

// Constants that should be used when building where statements
const (
	Alias_{{ $prefix }} = "{{ shortname $table_name }}"
	Table_{{ $prefix }}_With_Alias = "{{.Schema}}.{{ $table_name }} AS {{ shortname $table_name }}"
	Table_{{ $prefix }} = "{{.Schema}}.{{ $table_name }}"

{{- range .Fields }}
	Field_{{ $prefix }}_{{ .Name }} = "{{ .Col.ColumnName }}"
{{- end }}

{{- range .Fields }}
	Field_{{ $prefix }}_{{ .Name }}_With_Alias = "{{ shortname $table_name }}.{{ .Col.ColumnName }}"
{{- end }}

{{- range .Fields }}
	Field_{{ $prefix }}_{{ .Name }}_With_TableName= "{{ $table_name }}.{{ .Col.ColumnName }}"
{{- end }}
)

{{- $short := (shortname .Name "err" "res" "sqlstr" "db" "XOLog") -}}
{{- $table := (schema .Schema .Table.TableName) -}}
{{- if .Comment -}}
// {{ .Comment }}
{{- else -}}
// {{ .Name }} represents a row from '{{ $table }}'.
{{- end }}
type {{ .Name }} struct {
{{- range .Fields }}
	{{ if eq (retype .Type) "custom.Jsonb" -}}{{ .Name }} []byte `db:"{{ .Col.ColumnName }}" json:"{{ .Col.ColumnName }}"` // {{ .Col.ColumnName }}
    {{- else -}}{{ .Name }} {{ retype .Type }} `db:"{{ .Col.ColumnName }}" json:"{{ .Col.ColumnName }}"` // {{ .Col.ColumnName }}
    {{- end -}}
{{- end }}
{{- if .PrimaryKey }}

	// xo fields
	_exists, _deleted bool
{{ end }}
}

type {{ .Name }}s []*{{ .Name }}

func (t {{ $prefix }}) SelectColumnsWithCoalesce() []string {
    return []string{
         {{- range .Fields }}
               {{ if eq .Type "string" -}}fmt.Sprintf("COALESCE({{ shortname $table_name }}.{{ .Col.ColumnName }}, '%v') as {{ .Col.ColumnName }}", zero{{ $prefix }}.{{ .Name }}),{{ else if eq .Type "sql.NullString" -}}
               "{{ shortname $table_name }}.{{ .Col.ColumnName }}",{{ else if eq .Col.ColumnName "shipment_type" -}}
               "{{ shortname $table_name }}.{{ .Col.ColumnName }}",{{ else if eq .Type "sql.NullInt64" -}}
               "{{ shortname $table_name }}.{{ .Col.ColumnName }}",{{ else if eq .Type "pq.NullTime" -}}
               "{{ shortname $table_name }}.{{ .Col.ColumnName }}",{{ else if eq .Type "time.Time" -}}
               fmt.Sprintf("COALESCE({{ shortname $table_name }}.{{ .Col.ColumnName }}, '%v') as {{ .Col.ColumnName }}", zero{{ $prefix }}.{{ .Name }}.Format(time.RFC3339)),{{ else if eq (retype .Type) "custom.Jsonb" -}}
               "{{ shortname $table_name }}.{{ .Col.ColumnName }}",{{- else -}}
               fmt.Sprintf("COALESCE({{ shortname $table_name }}.{{ .Col.ColumnName }}, %v) as {{ .Col.ColumnName }}", zero{{ $prefix }}.{{ .Name }}),
               {{- end -}}
         {{- end }}
    }
}

func (t {{ $prefix }}) SelectColumns() []string {
    return []string{
         {{- range .Fields }}
              "{{ shortname $table_name }}.{{ .Col.ColumnName }}",
         {{- end }}
    }
}

func (t {{ $prefix }}) Columns(without ...string) []string {
	var str = "{{ colnames .Fields }}"
	for _, exc := range without {
		str = strings.Replace(str + ", ", exc + ", ", "", 1)
	}
	return strings.Split(strings.TrimRight(str, ", "), ", ")
}

func (t {{ $prefix }}) WithTable(col string) string {
    return fmt.Sprintf("{{ shortname  .Table.TableName }}.%s", col)
}

func  (t {{ $prefix }}) IsEmpty() bool {
    return reflect.DeepEqual(t, zero{{ $prefix }})
}

func (t {{ $prefix }}) Join(rightColumnTable string, leftColumnTable string) string {
    return fmt.Sprintf("{{ .Table.TableName }} AS {{ shortname .Table.TableName }} ON {{ shortname .Table.TableName }}.%s = %s", rightColumnTable, leftColumnTable)
}

func (t *{{ $prefix }}) ToMap() (map[string]interface{}) {
	return map[string]interface{}{
	{{- range .Fields }}
		"{{ .Col.ColumnName }}": t.{{ .Name }},
	{{- end }}
	}
}

func (t *{{ $prefix }}) Values(colNames ...string) (vals []interface{}) {
	m := t.ToMap()
	if _, ok := m["updated_at"]; ok {
		m["updated_at"] = time.Now()
	}

	for _, v := range colNames {
		vals = append(vals, m[v])
	}

	return vals
}

{{ if .PrimaryKey }}
// Exists determines if the {{ .Name }} exists in the database.
func ({{ $short }} *{{ .Name }}) Exists() bool {
	return {{ $short }}._exists
}

// Deleted provides information if the {{ .Name }} has been deleted from the database.
func ({{ $short }} *{{ .Name }}) Deleted() bool {
	return {{ $short }}._deleted
}

// Insert inserts the {{ .Name }} to the database.
func ({{ $short }} *{{ .Name }}) Insert(db XODB) error {
	var err error

	// if already exist, bail
	if {{ $short }}._exists {
		return errors.New("insert failed: already exists")
	}

{{ if .Table.ManualPk }}
	// sql insert query, primary key must be provided
	const sqlstr = `INSERT INTO {{ $table }} (` +
		`{{ colnames .Fields }}` +
		`) VALUES (` +
		`{{ colvals .Fields }}` +
		`)`

	// run query
	XOLog(sqlstr, {{ fieldnames .Fields $short }})
	_, err = db.Exec(sqlstr, {{ fieldnames .Fields $short }})
	if err != nil {
		return err
	}
{{ else }}
	// sql insert query, primary key provided by sequence
	const sqlstr = `INSERT INTO {{ $table }} (` +
		`{{ colnames .Fields .PrimaryKey.Name }}` +
		`) VALUES (` +
		`{{ colvals .Fields .PrimaryKey.Name }}` +
		`) RETURNING {{ colname .PrimaryKey.Col }}`

	// run query
	XOLog(sqlstr, {{ fieldnames .Fields $short .PrimaryKey.Name }})
	err = db.QueryRow(sqlstr, {{ fieldnames .Fields $short .PrimaryKey.Name }}).Scan(&{{ $short }}.{{ .PrimaryKey.Name }})
	if err != nil {
		return err
	}
{{ end }}

	// set existence
	{{ $short }}._exists = true

	return nil
}

{{ if ne (fieldnamesmulti .Fields $short .PrimaryKeyFields) "" }}
	// Update updates the {{ .Name }} in the database.
	func ({{ $short }} *{{ .Name }}) Update(db XODB) error {
		var err error

		{{ if gt ( len .PrimaryKeyFields ) 1 }}
			// sql query with composite primary key
			const sqlstr = `UPDATE {{ $table }} SET (` +
				`{{ colnamesmulti .Fields .PrimaryKeyFields }}` +
				`) = ( ` +
				`{{ colvalsmulti .Fields .xPrimaryKeyFields }}` +
				`) WHERE {{ colnamesquerymulti .PrimaryKeyFields " AND " (getstartcount .Fields .PrimaryKeyFields) nil }}`

			// run query
			XOLog(sqlstr, {{ fieldnamesmulti .Fields $short .PrimaryKeyFields }}, {{ fieldnames .PrimaryKeyFields $short}})
			_, err = db.Exec(sqlstr, {{ fieldnamesmulti .Fields $short .PrimaryKeyFields }}, {{ fieldnames .PrimaryKeyFields $short}})
		return err
		{{- else }}
			// sql query
			const sqlstr = `UPDATE {{ $table }} SET (` +
				`{{ colnames .Fields .PrimaryKey.Name }}` +
				`) = ( ` +
				`{{ colvals .Fields .PrimaryKey.Name }}` +
				`) WHERE {{ colname .PrimaryKey.Col }} = ${{ colcount .Fields .PrimaryKey.Name }}`

			// run query
			XOLog(sqlstr, {{ fieldnames .Fields $short .PrimaryKey.Name }}, {{ $short }}.{{ .PrimaryKey.Name }})
			_, err = db.Exec(sqlstr, {{ fieldnames .Fields $short .PrimaryKey.Name }}, {{ $short }}.{{ .PrimaryKey.Name }})
			return err
		{{- end }}
	}

	// Save saves the {{ .Name }} to the database.
	func ({{ $short }} *{{ .Name }}) Save(db XODB) error {
		if {{ $short }}.Exists() {
			return {{ $short }}.Update(db)
		}

		return {{ $short }}.Insert(db)
	}

	// Upsert performs an upsert for {{ .Name }}.
	//
	// NOTE: PostgreSQL 9.5+ only
	func ({{ $short }} *{{ .Name }}) Upsert(db XODB) error {
		var err error

		// if already exist, bail
		if {{ $short }}._exists {
			return errors.New("insert failed: already exists")
		}

		// sql query
		const sqlstr = `INSERT INTO {{ $table }} (` +
			`{{ colnames .Fields }}` +
			`) VALUES (` +
			`{{ colvals .Fields }}` +
			`) ON CONFLICT ({{ colnames .PrimaryKeyFields }}) DO UPDATE SET (` +
			`{{ colnames .Fields }}` +
			`) = (` +
			`{{ colprefixnames .Fields "EXCLUDED" }}` +
			`)`

		// run query
		XOLog(sqlstr, {{ fieldnames .Fields $short }})
		_, err = db.Exec(sqlstr, {{ fieldnames .Fields $short }})
		if err != nil {
			return err
		}

		// set existence
		{{ $short }}._exists = true

		return nil
}
{{ else }}
	// Update statements omitted due to lack of fields other than primary key
{{ end }}

// Delete deletes the {{ .Name }} from the database.
func ({{ $short }} *{{ .Name }}) Delete(db XODB) error {
	var err error

	// if doesn't exist, bail
	if !{{ $short }}._exists {
		return nil
	}

	// if deleted, bail
	if {{ $short }}._deleted {
		return nil
	}

	{{ if gt ( len .PrimaryKeyFields ) 1 }}
		// sql query with composite primary key
		const sqlstr = `DELETE FROM {{ $table }}  WHERE {{ colnamesquery .PrimaryKeyFields " AND " }}`

		// run query
		XOLog(sqlstr, {{ fieldnames .PrimaryKeyFields $short }})
		_, err = db.Exec(sqlstr, {{ fieldnames .PrimaryKeyFields $short }})
		if err != nil {
			return err
		}
	{{- else }}
		// sql query
		const sqlstr = `DELETE FROM {{ $table }} WHERE {{ colname .PrimaryKey.Col }} = $1`

		// run query
		XOLog(sqlstr, {{ $short }}.{{ .PrimaryKey.Name }})
		_, err = db.Exec(sqlstr, {{ $short }}.{{ .PrimaryKey.Name }})
		if err != nil {
			return err
		}
	{{- end }}

	// set deleted
	{{ $short }}._deleted = true

	return nil
}

func ({{ $short }} *{{ .Name }}s) Update(db XODB) error {
     var err error

    // sql insert query, primary key must be provided
    const sqlstr = `UPDATE {{ $table }} SET ` +
        {{- $n := len .Fields }}
        {{- range $i, $f := .Fields }}
            `{{ $f.Col.ColumnName }} = t.{{ $f.Col.ColumnName }}{{ if lt (add $i 1) $n }}, {{ end }}` +
        {{- end }}
        ` FROM UNNEST(` +
            {{- $n := len .Fields }}
            {{- range $i, $f := .Fields }}
                `${{ add $i 1 }}::{{ $f.Col.DataType }}[]{{ if lt (add $i 1) $n }}, {{ end }}` +
            {{- end }}
        `) as t({{ colnames .Fields }})` +
    {{ if gt ( len .PrimaryKeyFields ) 1 }}
        ` WHERE {{ $table_name }}.{{ colnamesquery .PrimaryKeyFields " AND " }}`
    {{- else }}
    	` WHERE {{ $table_name }}.{{ colname .PrimaryKey.Col }} = t.{{ colname .PrimaryKey.Col }}`
    {{- end }}

    batch := struct{
        {{- range .Fields }}
            {{ if eq (retype .Type) "custom.Jsonb" -}}{{ .Name }} [][]byte // {{ .Col.ColumnName }}
            {{- else -}}{{ .Name }} []{{ retype .Type }} // {{ .Col.ColumnName }}
            {{- end -}}
        {{- end }}
    }{}

    for _, item := range *{{ $short }} {
        {{- range .Fields }}
            batch.{{ .Name }} = append(batch.{{ .Name }}, item.{{ .Name }})
        {{- end }}
    }

    // run query
    _, err = db.Exec(
        sqlstr,
        {{- range .Fields }}
            batch.{{ .Name }},
        {{- end }}
    )
    if err != nil {
        return err
    }

    return nil
}
{{- end }}

func ({{ $short }} *{{ .Name }}s) Insert(db XODB) error {
    var err error

	// sql insert query, primary key must be provided
	const sqlstr = `INSERT INTO {{ $table }} (` +
		`{{ colnames .Fields }}` +
		`) SELECT * FROM UNNEST(` +
            {{- $n := len .Fields }}
            {{- range $i, $f := .Fields }}
                `${{ add $i 1 }}::{{ $f.Col.DataType }}[]{{ if lt (add $i 1) $n }}, {{ end }}` +
            {{- end }}
        `);`

    batch := struct{
        {{- range .Fields }}
        	{{ if eq (retype .Type) "custom.Jsonb" -}}{{ .Name }} [][]byte // {{ .Col.ColumnName }}
            {{- else -}}{{ .Name }} []{{ retype .Type }} // {{ .Col.ColumnName }}
            {{- end -}}
        {{- end }}
    }{}

    for _, item := range *{{ $short }} {
        {{- range .Fields }}
            batch.{{ .Name }} = append(batch.{{ .Name }}, item.{{ .Name }})
        {{- end }}
    }

    // run query
    _, err = db.Exec(
        sqlstr,
        {{- range .Fields }}
            batch.{{ .Name }},
        {{- end }}
    )
    if err != nil {
        return err
    }

    return nil
}