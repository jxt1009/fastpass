package main

import (
	"testing"
)

func TestGoogleClientIDCandidates_PrefersRequestClientID(t *testing.T) {
	t.Setenv("GOOGLE_CLIENT_ID", "env-client.apps.googleusercontent.com")

	got := googleClientIDCandidates("request-client.apps.googleusercontent.com")

	if len(got) != 2 {
		t.Fatalf("expected 2 client IDs, got %d (%v)", len(got), got)
	}
	if got[0] != "request-client.apps.googleusercontent.com" {
		t.Fatalf("expected request client ID first, got %q", got[0])
	}
	if got[1] != "env-client.apps.googleusercontent.com" {
		t.Fatalf("expected env client ID second, got %q", got[1])
	}
}

func TestGoogleClientIDCandidates_DeduplicatesAndTrims(t *testing.T) {
	t.Setenv("GOOGLE_CLIENT_ID", " env-client.apps.googleusercontent.com , request-client.apps.googleusercontent.com, env-client.apps.googleusercontent.com ")

	got := googleClientIDCandidates(" request-client.apps.googleusercontent.com ")

	if len(got) != 2 {
		t.Fatalf("expected 2 unique client IDs, got %d (%v)", len(got), got)
	}
	if got[0] != "request-client.apps.googleusercontent.com" {
		t.Fatalf("expected trimmed request client ID first, got %q", got[0])
	}
	if got[1] != "env-client.apps.googleusercontent.com" {
		t.Fatalf("expected trimmed env client ID second, got %q", got[1])
	}
}

func TestRedactGoogleClientID(t *testing.T) {
	got := redactGoogleClientID("761710305317-v7fqdoiqqveva29pc2461qm5ku7dadmp.apps.googleusercontent.com")
	want := "761710...nt.com"
	if got != want {
		t.Fatalf("expected redacted client ID %q, got %q", want, got)
	}
}
