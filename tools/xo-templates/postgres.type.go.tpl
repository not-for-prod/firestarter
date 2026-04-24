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
