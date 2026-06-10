package app

import (
	"reflect"
	"testing"
)

func TestParseGarage(t *testing.T) {
	tests := []struct {
		name    string
		blob    string
		want    []GarageCar
		wantErr bool
	}{
		{
			name: "empty string",
			blob: "",
			want: []GarageCar{},
		},
		{
			name: "whitespace only",
			blob: "   \n\t  ",
			want: []GarageCar{},
		},
		{
			name: "two cars with photos",
			blob: `[{"id":"a","make":"Honda","photo_url":"https://x/a.jpg"},{"id":"b","make":"BMW","photo_url":"https://x/b.jpg"}]`,
			want: []GarageCar{
				{ID: "a", PhotoURL: "https://x/a.jpg"},
				{ID: "b", PhotoURL: "https://x/b.jpg"},
			},
		},
		{
			name: "car without photo_url",
			blob: `[{"id":"a","make":"Honda"}]`,
			want: []GarageCar{{ID: "a", PhotoURL: ""}},
		},
		{
			name:    "malformed JSON",
			blob:    `[{"id":"a"`,
			wantErr: true,
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got, err := ParseGarage(tc.blob)
			if (err != nil) != tc.wantErr {
				t.Fatalf("ParseGarage() error = %v, wantErr %v", err, tc.wantErr)
			}
			if !tc.wantErr && !reflect.DeepEqual(got, tc.want) {
				t.Errorf("ParseGarage() = %+v, want %+v", got, tc.want)
			}
		})
	}
}

func TestIndexGaragePhotoURLs(t *testing.T) {
	cars := []GarageCar{
		{ID: "a", PhotoURL: "https://x/a.jpg"},
		{ID: "b", PhotoURL: "https://x/b.jpg"},
		{ID: "c", PhotoURL: ""},
		{ID: "", PhotoURL: "ignored"}, // empty id → skipped
	}
	got := IndexGaragePhotoURLs(cars)
	want := map[string]string{
		"a": "https://x/a.jpg",
		"b": "https://x/b.jpg",
		"c": "",
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("IndexGaragePhotoURLs() = %+v, want %+v", got, want)
	}
}

func TestBuildUserGarageIndex(t *testing.T) {
	t.Run("valid blob", func(t *testing.T) {
		idx, err := BuildUserGarageIndex(`[{"id":"a","photo_url":"https://x/a.jpg"}]`)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if idx["a"] != "https://x/a.jpg" {
			t.Errorf("idx[a] = %q, want %q", idx["a"], "https://x/a.jpg")
		}
	})
	t.Run("malformed blob returns error", func(t *testing.T) {
		_, err := BuildUserGarageIndex(`not json`)
		if err == nil {
			t.Error("expected error for malformed JSON, got nil")
		}
	})
}
