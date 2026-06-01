package app

import (
	"time"
)

// AchievementRequirement is the JSON shape the API returns for each
// achievement in the catalog. Mirrors the iOS AchievementRequirement.
type AchievementRequirement struct {
	Type      string   `json:"type"`
	Value     float64  `json:"value"`
	Condition *string  `json:"condition,omitempty"`
	Unit      string   `json:"unit,omitempty"`
}

// AchievementCatalogEntry is the public-facing shape of a single achievement
// definition. Mirrors the iOS Achievement struct, minus per-user progress.
type AchievementCatalogEntry struct {
	ID          string                `json:"id"`
	Title       string                `json:"title"`
	Description string                `json:"description"`
	Category    string                `json:"category"`
	Icon        string                `json:"icon"`
	Requirement AchievementRequirement `json:"requirement"`
}

// SourceKind values that populate UserAchievement.SourceKind.
const (
	SourceKindMaxSpeed        = "max_speed"
	SourceKindDriveCount      = "drive_count"
	SourceKindTotalDistance   = "total_distance"
	SourceKindBestZeroToSixty = "best_060"
	SourceKindConsecutiveDays = "consecutive_days"
	SourceKindSmoothness      = "smoothness"
)

// defaultCatalog is the authoritative list of achievements. iOS keeps a
// mirror of this list in Models/Achievement.swift. Keep them in sync.
//
// Adding a new entry here automatically makes it available on iOS and web
// (via the catalog endpoint) and eligible for evaluation on the next drive
// save.
var defaultCatalog = []AchievementCatalogEntry{
	{
		ID:          "first_drive",
		Title:       "First Drive",
		Description: "Complete your first recorded drive",
		Category:    "milestone",
		Icon:        "car.fill",
		Requirement: AchievementRequirement{Type: "drive_count", Value: 1, Unit: "drives"},
	},
	{
		ID:          "speed_50",
		Title:       "Half Century",
		Description: "Reach 50 mph",
		Category:    "speed",
		Icon:        "gauge.with.needle",
		Requirement: AchievementRequirement{Type: "max_speed", Value: 22.352, Unit: "m/s"}, // 50 mph
	},
	{
		ID:          "speed_100",
		Title:       "Century Club",
		Description: "Join the elite 100 mph club",
		Category:    "speed",
		Icon:        "speedometer",
		Requirement: AchievementRequirement{Type: "max_speed", Value: 44.704, Unit: "m/s"}, // 100 mph
	},
	{
		ID:          "speed_150",
		Title:       "Speed Demon",
		Description: "Hit the legendary 150 mph mark",
		Category:    "speed",
		Icon:        "bolt.fill",
		Requirement: AchievementRequirement{Type: "max_speed", Value: 67.056, Unit: "m/s"}, // 150 mph
	},
	{
		ID:          "distance_10",
		Title:       "Explorer",
		Description: "Drive a total of 10 miles",
		Category:    "distance",
		Icon:        "map.fill",
		Requirement: AchievementRequirement{Type: "total_distance", Value: 16093.4, Unit: "m"}, // 10 mi
	},
	{
		ID:          "distance_100",
		Title:       "Road Warrior",
		Description: "Drive a total of 100 miles",
		Category:    "distance",
		Icon:        "road.lanes",
		Requirement: AchievementRequirement{Type: "total_distance", Value: 160934, Unit: "m"},
	},
	{
		ID:          "distance_1000",
		Title:       "Mile Crusher",
		Description: "Drive a total of 1,000 miles",
		Category:    "distance",
		Icon:        "globe",
		Requirement: AchievementRequirement{Type: "total_distance", Value: 1609344, Unit: "m"},
	},
	{
		ID:          "drives_10",
		Title:       "Getting Started",
		Description: "Complete 10 recorded drives",
		Category:    "milestone",
		Icon:        "circle.fill",
		Requirement: AchievementRequirement{Type: "drive_count", Value: 10, Unit: "drives"},
	},
	{
		ID:          "drives_50",
		Title:       "Experienced Driver",
		Description: "Complete 50 recorded drives",
		Category:    "milestone",
		Icon:        "award.fill",
		Requirement: AchievementRequirement{Type: "drive_count", Value: 50, Unit: "drives"},
	},
	{
		ID:          "drives_100",
		Title:       "Dedicated Tracker",
		Description: "Complete 100 recorded drives",
		Category:    "milestone",
		Icon:        "checkmark.circle.fill",
		Requirement: AchievementRequirement{Type: "drive_count", Value: 100, Unit: "drives"},
	},
	{
		ID:          "streak_3",
		Title:       "Getting Consistent",
		Description: "Drive on 3 consecutive days",
		Category:    "consistency",
		Icon:        "calendar",
		Requirement: AchievementRequirement{Type: "consecutive_days", Value: 3, Unit: "days"},
	},
	{
		ID:          "streak_7",
		Title:       "Week Warrior",
		Description: "Drive on 7 consecutive days",
		Category:    "consistency",
		Icon:        "calendar",
		Requirement: AchievementRequirement{Type: "consecutive_days", Value: 7, Unit: "days"},
	},
	{
		ID:          "streak_30",
		Title:       "Monthly Master",
		Description: "Drive on 30 consecutive days",
		Category:    "consistency",
		Icon:        "star.fill",
		Requirement: AchievementRequirement{Type: "consecutive_days", Value: 30, Unit: "days"},
	},
	{
		ID:          "sub_6_club",
		Title:       "Sub-6-Second Club",
		Description: "Achieve 0-60 mph in under 6 seconds",
		Category:    "performance",
		Icon:        "timer",
		Requirement: AchievementRequirement{Type: "best_060", Value: 6.0, Unit: "s"},
	},
	{
		ID:          "sub_5_club",
		Title:       "Sub-5-Second Club",
		Description: "Achieve 0-60 mph in under 5 seconds",
		Category:    "performance",
		Icon:        "bolt.fill",
		Requirement: AchievementRequirement{Type: "best_060", Value: 5.0, Unit: "s"},
	},
	{
		ID:          "smooth_operator",
		Title:       "Smooth Operator",
		Description: "Maintain 90% driving smoothness score",
		Category:    "consistency",
		Icon:        "waveform.path",
		Requirement: AchievementRequirement{Type: "smoothness", Value: 90.0, Unit: "%"},
	},
	{
		ID:          "midnight_driver",
		Title:       "Midnight Driver",
		Description: "Complete a drive after midnight",
		Category:    "special",
		Icon:        "moon.stars.fill",
		Requirement: AchievementRequirement{Type: "drive_count", Value: 1, Unit: "drives", Condition: stringPtr("after_midnight")},
	},
	{
		ID:          "weekend_warrior",
		Title:       "Weekend Warrior",
		Description: "Complete 10 drives on weekends",
		Category:    "special",
		Icon:        "sun.max",
		Requirement: AchievementRequirement{Type: "drive_count", Value: 10, Unit: "drives", Condition: stringPtr("weekend")},
	},
}

func stringPtr(s string) *string { return &s }

// catalogByID returns a pointer to the catalog entry for the given ID.
func catalogByID(id string) *AchievementCatalogEntry {
	for i := range defaultCatalog {
		if defaultCatalog[i].ID == id {
			return &defaultCatalog[i]
		}
	}
	return nil
}

// evaluationInputs collects the aggregate values needed to evaluate every
// achievement in the catalog for a user. Computed in one SQL pass and
// shared across all catalog entries.
type evaluationInputs struct {
	MaxSpeed        float64
	TotalDistance   float64
	DriveCount      int
	BestZeroToSixty *float64
	Drives          []Drive // for consecutive_days + filtered drive_count
}

// loadEvaluationInputs gathers the per-user aggregates required to evaluate
// every catalog entry.
func loadEvaluationInputs(userID uint) (evaluationInputs, error) {
	var in evaluationInputs

	// Max speed, total distance, drive count
	type aggRow struct {
		MaxSpeed      float64
		TotalDistance float64
		DriveCount    int
	}
	var agg aggRow
	if err := db.Raw(`
		SELECT COALESCE(MAX(max_speed), 0) AS max_speed,
		       COALESCE(SUM(distance), 0)  AS total_distance,
		       COUNT(id)                  AS drive_count
		FROM drives WHERE user_id = ?`, userID).Scan(&agg).Error; err != nil {
		return in, err
	}
	in.MaxSpeed = agg.MaxSpeed
	in.TotalDistance = agg.TotalDistance
	in.DriveCount = agg.DriveCount

	// Best 0-60 (lowest)
	var best *float64
	var bestVal float64
	// COALESCE handles the empty-set case: MIN over zero rows returns SQL
	// NULL, which can't be scanned directly into a float64.
	if err := db.Raw(`SELECT COALESCE(MIN(best_060_time), 0) FROM drives WHERE user_id = ? AND best_060_time IS NOT NULL`, userID).Scan(&bestVal).Error; err != nil {
		return in, err
	}
	if bestVal > 0 {
		best = &bestVal
	}
	in.BestZeroToSixty = best

	// Per-drive metadata for consecutive_days + drive_count filters
	if err := db.Where("user_id = ?", userID).Order("start_time ASC").Find(&in.Drives).Error; err != nil {
		return in, err
	}
	return in, nil
}

// evaluationResult describes an achievement that just crossed its threshold
// and should be persisted.
type evaluationResult struct {
	AchievementID  string
	SourceKind     string
	SourceValue    float64
	SourceDriveID  *uint
}

// evaluate checks every catalog entry against the inputs and returns the
// achievements the user has newly satisfied. Already-unlocked achievements
// are filtered by the caller before persistence.
func evaluate(userID uint, inputs evaluationInputs) []evaluationResult {
	var unlocked []evaluationResult

	for _, entry := range defaultCatalog {
		switch entry.Requirement.Type {
		case "drive_count":
			count := int64(0)
			if entry.Requirement.Condition != nil {
				count = int64(filteredDriveCount(inputs.Drives, *entry.Requirement.Condition))
			} else {
				count = int64(inputs.DriveCount)
			}
			if float64(count) >= entry.Requirement.Value {
				sourceDrive := newestMatchingDrive(inputs.Drives, entry.Requirement.Condition)
				var srcID *uint
				if sourceDrive != nil {
					id := sourceDrive.ID
					srcID = &id
				}
				unlocked = append(unlocked, evaluationResult{
					AchievementID: entry.ID,
					SourceKind:    SourceKindDriveCount,
					SourceValue:   float64(count),
					SourceDriveID: srcID,
				})
			}
		case "max_speed":
			if inputs.MaxSpeed >= entry.Requirement.Value {
				// Source drive = drive with the max speed for that user
				sourceDrive := driveWithMaxSpeed(inputs.Drives)
				var srcID *uint
				if sourceDrive != nil {
					id := sourceDrive.ID
					srcID = &id
				}
				unlocked = append(unlocked, evaluationResult{
					AchievementID: entry.ID,
					SourceKind:    SourceKindMaxSpeed,
					SourceValue:   inputs.MaxSpeed,
					SourceDriveID: srcID,
				})
			}
		case "total_distance":
			if inputs.TotalDistance >= entry.Requirement.Value {
				// Source drive = most recent drive (cumulative requirement)
				sourceDrive := mostRecentDrive(inputs.Drives)
				var srcID *uint
				if sourceDrive != nil {
					id := sourceDrive.ID
					srcID = &id
				}
				unlocked = append(unlocked, evaluationResult{
					AchievementID: entry.ID,
					SourceKind:    SourceKindTotalDistance,
					SourceValue:   inputs.TotalDistance,
					SourceDriveID: srcID,
				})
			}
		case "best_060":
			if inputs.BestZeroToSixty != nil && *inputs.BestZeroToSixty <= entry.Requirement.Value {
				sourceDrive := driveWithBestZeroToSixty(inputs.Drives)
				var srcID *uint
				if sourceDrive != nil {
					id := sourceDrive.ID
					srcID = &id
				}
				unlocked = append(unlocked, evaluationResult{
					AchievementID: entry.ID,
					SourceKind:    SourceKindBestZeroToSixty,
					SourceValue:   *inputs.BestZeroToSixty,
					SourceDriveID: srcID,
				})
			}
		case "consecutive_days":
			days := consecutiveDriveDays(inputs.Drives)
			if float64(days) >= entry.Requirement.Value {
				sourceDrive := mostRecentDrive(inputs.Drives)
				var srcID *uint
				if sourceDrive != nil {
					id := sourceDrive.ID
					srcID = &id
				}
				unlocked = append(unlocked, evaluationResult{
					AchievementID: entry.ID,
					SourceKind:    SourceKindConsecutiveDays,
					SourceValue:   float64(days),
					SourceDriveID: srcID,
				})
			}
		case "smoothness":
			// iOS has a placeholder implementation; mirror the no-op here.
			// We don't compute smoothness server-side yet.
		}
	}
	return unlocked
}

// evaluateForUser runs the full evaluation and persists any new unlocks. It
// returns the set of currently-unlocked achievements so the client can sync.
func evaluateForUser(userID uint) ([]UnlockedAchievement, error) {
	inputs, err := loadEvaluationInputs(userID)
	if err != nil {
		return nil, err
	}
	candidate := evaluate(userID, inputs)

	if len(candidate) == 0 {
		// Nothing to add; still return currently-unlocked for client sync.
		return loadUnlockedAchievements(userID)
	}

	// Load existing unlocks to dedupe
	existing := map[string]bool{}
	var existingRows []UserAchievement
	if err := db.Where("user_id = ?", userID).Find(&existingRows).Error; err != nil {
		return nil, err
	}
	for _, row := range existingRows {
		existing[row.AchievementID] = true
	}

	now := time.Now().UTC()
	for _, c := range candidate {
		if existing[c.AchievementID] {
			continue
		}
		row := UserAchievement{
			UserID:        userID,
			AchievementID: c.AchievementID,
			UnlockedAt:    now,
			SourceDriveID: c.SourceDriveID,
			SourceKind:    c.SourceKind,
			SourceValue:   c.SourceValue,
		}
		if err := db.Create(&row).Error; err != nil {
			return nil, err
		}
	}

	// Return full unlocked set so clients can sync exactly
	return loadUnlockedAchievements(userID)
}

// UnlockedAchievement is the public-facing shape of a single unlocked
// achievement row. The (UserID, AchievementID) pair is hidden from clients.
type UnlockedAchievement struct {
	AchievementID string    `json:"achievement_id"`
	UnlockedAt    time.Time `json:"unlocked_at"`
	SourceDriveID *uint     `json:"source_drive_id"`
	SourceKind    string    `json:"source_kind"`
	SourceValue   float64   `json:"source_value"`
}

func loadUnlockedAchievements(userID uint) ([]UnlockedAchievement, error) {
	var rows []UserAchievement
	if err := db.Where("user_id = ?", userID).Order("unlocked_at DESC").Find(&rows).Error; err != nil {
		return nil, err
	}
	out := make([]UnlockedAchievement, 0, len(rows))
	for _, r := range rows {
		out = append(out, UnlockedAchievement{
			AchievementID: r.AchievementID,
			UnlockedAt:    r.UnlockedAt,
			SourceDriveID: r.SourceDriveID,
			SourceKind:    r.SourceKind,
			SourceValue:   r.SourceValue,
		})
	}
	return out, nil
}

func loadUnlockedAchievementsForUsername(username string) ([]UnlockedAchievement, error) {
	var user User
	if err := db.Where("username = ? AND is_public = true", username).First(&user).Error; err != nil {
		return nil, err
	}
	return loadUnlockedAchievements(user.ID)
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

func filteredDriveCount(drives []Drive, condition string) int {
	n := 0
	for _, d := range drives {
		if driveMatchesCondition(d, condition) {
			n++
		}
	}
	return n
}

func driveMatchesCondition(d Drive, condition string) bool {
	switch condition {
	case "weekend":
		wd := d.StartTime.Weekday()
		return wd == time.Saturday || wd == time.Sunday
	case "after_midnight":
		h := d.StartTime.Hour()
		return h >= 0 && h < 6
	default:
		return false
	}
}

func newestMatchingDrive(drives []Drive, condition *string) *Drive {
	var best *Drive
	for i := range drives {
		d := &drives[i]
		if condition != nil && !driveMatchesCondition(*d, *condition) {
			continue
		}
		if best == nil || d.StartTime.After(best.StartTime) {
			best = d
		}
	}
	return best
}

func driveWithMaxSpeed(drives []Drive) *Drive {
	var best *Drive
	for i := range drives {
		d := &drives[i]
		if best == nil || d.MaxSpeed > best.MaxSpeed {
			best = d
		}
	}
	return best
}

func mostRecentDrive(drives []Drive) *Drive {
	if len(drives) == 0 {
		return nil
	}
	most := &drives[0]
	for i := 1; i < len(drives); i++ {
		if drives[i].StartTime.After(most.StartTime) {
			most = &drives[i]
		}
	}
	return most
}

func driveWithBestZeroToSixty(drives []Drive) *Drive {
	var best *Drive
	for i := range drives {
		d := &drives[i]
		if d.Best060Time == nil {
			continue
		}
		if best == nil || best.Best060Time == nil || *d.Best060Time < *best.Best060Time {
			best = d
		}
	}
	return best
}

func consecutiveDriveDays(drives []Drive) int {
	if len(drives) == 0 {
		return 0
	}
	// Walk start times; count the longest run of consecutive UTC days.
	const oneDay = 24 * time.Hour
	dates := make([]time.Time, 0, len(drives))
	for _, d := range drives {
		dates = append(dates, d.StartTime.UTC().Truncate(oneDay))
	}
	maxRun, run := 1, 1
	for i := 1; i < len(dates); i++ {
		// `time.Duration` is nanoseconds; convert the gap to whole days
		// explicitly. Using an untyped `24*60*60` constant here would
		// truncate to nanoseconds and silently break the streak check.
		delta := int(dates[i].Sub(dates[i-1]) / oneDay)
		if delta == 1 {
			run++
			if run > maxRun {
				maxRun = run
			}
		} else if delta > 1 {
			run = 1
		}
		// delta == 0 (same day) leaves the run intact
	}
	return maxRun
}