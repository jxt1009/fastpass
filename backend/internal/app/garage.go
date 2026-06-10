package app

import (
	"bytes"
	"encoding/json"
	"errors"
)

// GarageCar mirrors the JSON shape of one element of the User.Garage array.
// Only the fields we currently read are declared; add more here as needed.
type GarageCar struct {
	ID       string `json:"id"`
	PhotoURL string `json:"photo_url"`
}

// ParseGarage unmarshals the User.Garage text column into a slice of cars.
// Returns an empty slice (no error) for empty/whitespace input, an error
// for malformed JSON, and propagates unmarshal errors for type mismatches.
func ParseGarage(blob string) ([]GarageCar, error) {
	raw := []byte(blob)
	if len(bytes.TrimSpace(raw)) == 0 {
		raw = []byte("[]")
	}
	var cars []GarageCar
	if err := json.Unmarshal(raw, &cars); err != nil {
		return nil, err
	}
	return cars, nil
}

// IndexGaragePhotoURLs returns a map keyed by GarageCar.ID whose values are
// each car's photo_url ("" if absent). The index is built in O(n) over
// `cars`. This is the shape we want for the leaderboard lookup: a single
// map per user that we can query by carID in O(1).
func IndexGaragePhotoURLs(cars []GarageCar) map[string]string {
	out := make(map[string]string, len(cars))
	for _, c := range cars {
		if c.ID == "" {
			continue
		}
		out[c.ID] = c.PhotoURL
	}
	return out
}

// BuildUserGarageIndex is a convenience that combines ParseGarage and
// IndexGaragePhotoURLs. A malformed garage blob produces a nil index and
// an error; callers should treat that as "no photo available" for the
// affected user and continue.
func BuildUserGarageIndex(blob string) (map[string]string, error) {
	cars, err := ParseGarage(blob)
	if err != nil {
		return nil, err
	}
	return IndexGaragePhotoURLs(cars), nil
}

// ErrGarageBlobInvalid is returned by ParseGarage when the blob is not
// valid JSON. (Currently unused externally but reserved for callers that
// want to distinguish malformed JSON from other parse failures.)
var ErrGarageBlobInvalid = errors.New("garage blob is not valid JSON")
